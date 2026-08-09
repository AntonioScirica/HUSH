import Foundation
import CryptoKit

/// Chiave di recupero: la via d'ingresso di scorta.
///
/// Senza qualcosa del genere, master password dimenticata vuol dire vault
/// persi per sempre — non esiste nessuno a cui chiederla, perché non esiste
/// nessun server. È lo stesso motivo per cui 1Password ti fa stampare
/// l'Emergency Kit al primo avvio.
///
/// Come funziona: si genera una chiave lunga e casuale, la si mostra **una
/// volta sola**, e con quella si cifra la master password in un file a parte.
/// Chi ha la chiave di recupero riapre lo scrigno; chi ha solo il file non ne
/// ricava niente.
///
/// Ne discende una cosa da dire chiaro a chi la usa: **la chiave di recupero
/// vale quanto la master password**. Chi se la procura entra. Va tenuta dove
/// terresti il passaporto, non in un file sul desktop accanto ai vault.
enum RecoveryKit {
    enum Failure: Error, LocalizedError {
        case none
        case wrongKey

        var errorDescription: String? {
            switch self {
            case .none:     return "Non c'è nessuna chiave di recupero per questo scrigno."
            case .wrongKey: return "Questa chiave di recupero non è valida."
            }
        }
    }

    /// Alfabeto senza caratteri che si confondono a leggerli su carta: niente
    /// 0/O, 1/I/L, 8/B. Chi ricopia a mano la chiave non deve sbagliare.
    private static let alphabet = Array("23456789ACDEFGHJKMNPQRTUVWXYZ")

    private static var fileURL: URL {
        VaultFileManager.shared.projectsDirectory.appendingPathComponent("recovery.dat")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Genera una chiave nuova e ci cifra dentro la master password.
    /// Restituisce la chiave in chiaro: è l'unica volta che si può leggere.
    static func create(masterPassword: String) throws -> String {
        // 30 caratteri su 29 simboli ≈ 145 bit: indovinarla è fuori discussione
        var key = ""
        for i in 0..<30 {
            if i > 0 && i % 5 == 0 { key.append("-") }
            key.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }

        var saltBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = Data(saltBytes)

        let sealed = try AES.GCM.seal(Data(masterPassword.utf8), using: symmetricKey(from: key, salt: salt))
        guard let combined = sealed.combined else { throw Failure.wrongKey }

        // salt in testa, poi la busta cifrata
        try (salt + combined).write(to: fileURL, options: [.atomic, .completeFileProtection])
        return key
    }

    /// Restituisce la master password, se la chiave è quella giusta.
    static func recover(with key: String) throws -> String {
        guard let blob = try? Data(contentsOf: fileURL), blob.count > 32 else { throw Failure.none }
        let salt = blob.prefix(32)
        let sealed = blob.dropFirst(32)

        // si accetta scritta come viene: con o senza trattini, in minuscolo
        let normalized = normalize(key)
        guard let box = try? AES.GCM.SealedBox(combined: sealed),
              let plain = try? AES.GCM.open(box, using: symmetricKey(from: normalized, salt: salt)),
              let password = String(data: plain, encoding: .utf8)
        else { throw Failure.wrongKey }
        return password
    }

    static func remove() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Toglie trattini e spazi e porta in maiuscolo: chi ricopia la chiave a
    /// mano non deve indovinare anche la punteggiatura.
    static func normalize(_ key: String) -> String {
        key.uppercased().filter { alphabet.contains($0) }
    }

    /// La chiave ha già la sua entropia (145 bit), quindi non serve un KDF
    /// lento: basta derivarne una chiave simmetrica con HKDF.
    private static func symmetricKey(from key: String, salt: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: Data(normalize(key).utf8)),
            salt: salt,
            info: Data("scrigno.recovery".utf8),
            outputByteCount: 32
        )
    }
}
