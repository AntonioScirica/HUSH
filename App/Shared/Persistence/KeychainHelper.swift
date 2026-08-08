import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unhandled(OSStatus)
    case notFound
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unhandled(let status): return "Errore Keychain (\(status))."
        case .notFound: return "Nessuna password salvata."
        case .encodingFailed: return "Errore interno di codifica."
        }
    }
}

/// Salva la master password nel Portachiavi, protetta da Face ID/Touch ID
/// (`biometryCurrentSet`): il sistema chiede la biometria ogni volta che il
/// valore viene letto, senza bisogno di gestire manualmente LocalAuthentication.
///
/// L'app principale e l'estensione AutoFill dichiarano lo STESSO
/// `keychain-access-groups` nelle rispettive entitlements — per questo qui
/// non specifichiamo esplicitamente `kSecAttrAccessGroup`: iOS usa di default
/// il (solo) gruppo dichiarato, che risulta quindi condiviso automaticamente.
enum SharedKeychain {
    private static let service = "com.antonioscirica.scrigno.masterpassword"
    private static let account = "vault"

    static var hasStoredPassword: Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        // kSecUseAuthenticationUIFail: verifica solo se l'item esiste, senza
        // mai mostrare il prompt biometrico.
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func store(password: String) throws {
        guard let data = password.data(using: .utf8) else { throw KeychainError.encodingFailed }
        delete()

        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil
        ) else {
            throw KeychainError.unhandled(errSecParam)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    /// La lettura richiede automaticamente Face ID/Touch ID (o il codice del
    /// dispositivo) perché l'item è protetto da `biometryCurrentSet`.
    static func retrieve(prompt: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: prompt,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound { throw KeychainError.notFound }
            throw KeychainError.unhandled(status)
        }
        return password
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
