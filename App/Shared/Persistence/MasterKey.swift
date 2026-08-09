import Foundation
import CryptoKit
import VaultCore
import Security
import LocalAuthentication

/// Una sola password per tutto lo scrigno.
///
/// Ogni progetto è un `.kdbx` a sé, ma la chiave è sempre questa: così si
/// entra una volta e si ha accesso a tutti i cassetti. La password vera non
/// viene mai salvata in chiaro — su disco resta solo un *verificatore*
/// (hash salato e iterato) che serve unicamente a dire "sì, è quella giusta"
/// senza dover decifrare un vault. La cifratura reale dei file resta quella
/// di VaultCore (AES-256 + Argon2id).
enum MasterKey {
    private static let saltKey = "scrigno.master.salt"
    private static let verifierKey = "scrigno.master.verifier"
    private static let biometryKey = "scrigno.master.biometry"
    private static let lastTypedKey = "scrigno.master.lastTyped"

    /// Ogni tanto la password va comunque digitata: col dito soltanto la si
    /// dimentica, e qui non c'è nessun "password dimenticata" a cui appellarsi.
    static var typeAgainAfter: TimeInterval {
        TimeInterval(Preferences.typeAgainDays) * 24 * 60 * 60
    }

    /// Iterazioni del verificatore: rende inutile provare le password a
    /// tappeto contro il file di preferenze.
    private static let iterations = 150_000

    /// Password della sessione corrente: vive solo in memoria, sparisce col
    /// blocco e alla chiusura dell'app.
    private(set) static var session: String?

    static var isConfigured: Bool {
        UserDefaults.standard.data(forKey: verifierKey) != nil
    }

    static var isUnlocked: Bool { session != nil }

    /// Primo avvio: fissa la master password.
    static func configure(password: String) {
        let salt = randomSalt()
        UserDefaults.standard.set(salt, forKey: saltKey)
        UserDefaults.standard.set(verifier(password, salt: salt), forKey: verifierKey)
        session = password
        markTyped()
    }

    /// Ritorna `false` se la password non combacia (senza aprire nulla).
    @discardableResult
    static func unlock(password: String) -> Bool {
        guard matches(password) else { return false }
        session = password
        markTyped()
        return true
    }

    /// La password combacia col verificatore salvato?
    ///
    /// Accetta anche il vecchio verificatore a SHA-256 e, se è quello, lo
    /// rifà subito con Argon2id: chi aveva già configurato l'app entra come
    /// sempre e si ritrova aggiornato senza accorgersene.
    private static func matches(_ password: String) -> Bool {
        guard let salt = UserDefaults.standard.data(forKey: saltKey),
              let stored = UserDefaults.standard.data(forKey: verifierKey) else { return false }

        if verifier(password, salt: salt) == stored { return true }

        guard legacyVerifier(password, salt: salt) == stored else { return false }
        UserDefaults.standard.set(verifier(password, salt: salt), forKey: verifierKey)
        return true
    }

    // MARK: - Promemoria periodico

    private static func markTyped() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastTypedKey)
    }

    /// Da quanto non si digita la password a mano.
    static var sinceTyped: TimeInterval {
        let last = UserDefaults.standard.double(forKey: lastTypedKey)
        guard last > 0 else { return .greatestFiniteMagnitude }
        return Date().timeIntervalSince1970 - last
    }

    /// Scaduto l'intervallo il dito non basta più: si riscrive la password.
    static var mustTypePassword: Bool { sinceTyped >= typeAgainAfter }

    static func lock() { session = nil }

    // MARK: - Biometria (facoltativa)

    /// Touch ID / Face ID disponibile su questa macchina.
    static var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    static var biometryEnabled: Bool {
        UserDefaults.standard.bool(forKey: biometryKey) && SharedKeychain.hasStoredPassword
    }

    static func enableBiometry(password: String) throws {
        try SharedKeychain.store(password: password)
        UserDefaults.standard.set(true, forKey: biometryKey)
    }

    static func disableBiometry() {
        SharedKeychain.delete()
        UserDefaults.standard.set(false, forKey: biometryKey)
    }

    /// Il dito è utilizzabile solo se attivo E se non è scaduto il giro in
    /// cui la password va comunque riscritta.
    static var biometryUsable: Bool { biometryEnabled && !mustTypePassword }

    /// Sblocca col dito. Su macOS la biometria la chiede l'app (LAContext) e
    /// solo dopo si legge il Portachiavi; su iOS ci pensa il Portachiavi.
    static func unlockWithBiometry(completion: @escaping (Bool) -> Void) {
        guard biometryUsable else { completion(false); return }

        #if os(macOS)
        let context = LAContext()
        context.localizedCancelTitle = "Annulla"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "sbloccare Scrigno") { ok, _ in
            DispatchQueue.main.async {
                guard ok, let password = try? SharedKeychain.retrieve(prompt: "Sblocca Scrigno") else {
                    completion(false)
                    return
                }
                // sbloccato col dito: la password NON conta come digitata,
                // altrimenti il promemoria non scatterebbe mai
                guard matches(password) else {
                    completion(false)
                    return
                }
                session = password
                completion(true)
            }
        }
        #else
        guard let password = try? SharedKeychain.retrieve(prompt: "Sblocca Scrigno") else {
            completion(false)
            return
        }
        guard matches(password) else {
            completion(false)
            return
        }
        session = password
        completion(true)
        #endif
    }

    // MARK: - Interna

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    /// Il verificatore si deriva con **Argon2id**, gli stessi parametri dei
    /// file .kdbx.
    ///
    /// Prima era una catena di SHA-256 ripetuta 150.000 volte: robetta per una
    /// scheda grafica, che ne calcola miliardi al secondo. E siccome il
    /// verificatore sta nelle preferenze, in chiaro, chi copiava quel file
    /// poteva indovinare offline la master password molto più in fretta di
    /// quanto avrebbe fatto attaccando un vault — per poi aprirli tutti.
    /// Era l'anello debole di tutta la catena.
    ///
    /// Argon2id costa memoria oltre che tempo (64 MiB a tentativo), e toglie
    /// alle schede grafiche il loro vantaggio: adesso indovinare la password
    /// dal verificatore non è più facile che attaccare i vault.
    private static func verifier(_ password: String, salt: Data) -> Data {
        if let key = try? Argon2.derive(password: password, salt: Array(salt)) {
            return Data(key)
        }
        // Ripiego difensivo: se Argon2 non risponde è meglio un verificatore
        // debole che un'app che non si apre più. Non custodisce nulla: i
        // vault restano cifrati con Argon2id comunque.
        return legacyVerifier(password, salt: salt)
    }

    /// Il verificatore com'era prima: serve solo a riconoscere le
    /// installazioni vecchie e convertirle al primo ingresso.
    private static func legacyVerifier(_ password: String, salt: Data) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(password.utf8)))
        for _ in 1..<iterations {
            digest = Data(SHA256.hash(data: digest + salt))
        }
        return digest
    }
}
