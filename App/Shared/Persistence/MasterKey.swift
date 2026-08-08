import Foundation
import CryptoKit
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
    }

    /// Ritorna `false` se la password non combacia (senza aprire nulla).
    @discardableResult
    static func unlock(password: String) -> Bool {
        guard let salt = UserDefaults.standard.data(forKey: saltKey),
              let stored = UserDefaults.standard.data(forKey: verifierKey),
              verifier(password, salt: salt) == stored else { return false }
        session = password
        return true
    }

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

    /// Sblocca col dito. Il prompt di sistema arriva dal Portachiavi stesso,
    /// perché l'elemento è protetto da `biometryCurrentSet`.
    static func unlockWithBiometry() -> Bool {
        guard biometryEnabled,
              let password = try? SharedKeychain.retrieve(prompt: "Sblocca Scrigno") else { return false }
        return unlock(password: password)
    }

    // MARK: - Interna

    private static func randomSalt() -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private static func verifier(_ password: String, salt: Data) -> Data {
        var digest = Data(SHA256.hash(data: salt + Data(password.utf8)))
        for _ in 1..<iterations {
            digest = Data(SHA256.hash(data: digest + salt))
        }
        return digest
    }
}
