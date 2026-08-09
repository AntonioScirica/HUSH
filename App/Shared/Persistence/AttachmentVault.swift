import Foundation
import CryptoKit

/// Allegati dei documenti, cifrati.
///
/// Prima il file scelto veniva semplicemente copiato in Application Support,
/// in chiaro: un gestore di password che promette di custodire un documento e
/// poi lo lascia leggibile a chiunque apra quella cartella. Ora ogni allegato
/// viene cifrato con AES-GCM e una chiave sua, casuale; la chiave finisce
/// dentro al `.kdbx` come campo protetto, quindi è custodita dal vault esatta-
/// mente come una password.
///
/// AES-GCM e non solo AES: oltre a nascondere il contenuto ne verifica
/// l'integrità, quindi un file manomesso viene rifiutato invece di essere
/// restituito corrotto.
enum AttachmentVault {
    enum Failure: Error, LocalizedError {
        case noKey
        case corrupt

        var errorDescription: String? {
            switch self {
            case .noKey:   return "L'allegato non ha una chiave valida."
            case .corrupt: return "L'allegato è danneggiato o è stato manomesso."
            }
        }
    }

    /// Cifra il file e lo salva. Restituisce il percorso e la chiave da
    /// riporre nel vault (in base64).
    static func store(_ source: URL) throws -> (path: String, key: String) {
        let plain = try Data(contentsOf: source)
        let key = SymmetricKey(size: .bits256)
        let sealed = try AES.GCM.seal(plain, using: key)
        guard let blob = sealed.combined else { throw Failure.corrupt }

        // Il nome sul disco non dice più che file sia: prima ci si leggeva
        // "carta-identita.pdf" senza nemmeno aprirlo.
        let dest = VaultFileManager.shared.attachmentsDirectory
            .appendingPathComponent("\(UUID().uuidString).bin")
        try blob.write(to: dest, options: [.atomic, .completeFileProtection])

        let raw = key.withUnsafeBytes { Data($0) }
        return (dest.path, raw.base64EncodedString())
    }

    /// Rilegge un allegato in chiaro, in memoria.
    static func load(path: String, key base64: String) throws -> Data {
        guard let raw = Data(base64Encoded: base64) else { throw Failure.noKey }
        let blob = try Data(contentsOf: URL(fileURLWithPath: path))
        let box = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(box, using: SymmetricKey(data: raw))
    }

    /// Riscrive un allegato in chiaro dove dice l'utente (esportazione).
    static func export(path: String, key: String, to destination: URL) throws {
        try load(path: path, key: key).write(to: destination, options: .atomic)
    }

    static func remove(path: String) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }
}
