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

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        #if os(iOS)
        // Su iOS l'elemento si protegge da sé: il sistema chiede la biometria
        // a ogni lettura, senza passare da LocalAuthentication.
        guard let access = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil
        ) else {
            throw KeychainError.unhandled(errSecParam)
        }
        query[kSecAttrAccessControl as String] = access
        #else
        // Su macOS no: SecAccessControl con biometria vuole il portachiavi
        // "data protection", che a sua volta pretende le entitlement di
        // keychain-access-group. Questo target non ne ha (niente sandbox, per
        // poter leggere i .kdbx ovunque), quindi SecItemAdd falliva ed è per
        // questo che il dito non funzionava. Qui l'elemento è normale e la
        // biometria la chiede l'app, con LAContext, prima di leggerlo.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // ...e l'app si mette da sola fra le applicazioni fidate dell'ACL.
        // Senza, il portachiavi "login" chiede la password di sistema a ogni
        // lettura, perché non riconosce chi sta chiedendo.
        if let access = selfTrustedAccess() {
            query[kSecAttrAccess as String] = access
        }
        #endif

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
    }

    /// Su iOS la lettura fa scattare da sola Face ID/Touch ID. Su macOS va
    /// chiamata SOLO dopo che LAContext ha già autenticato l'utente.
    static func retrieve(prompt: String) throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        #if os(iOS)
        query[kSecUseOperationPrompt as String] = prompt
        #endif
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

    #if os(macOS)
    /// ACL del portachiavi "login" che elenca questa stessa app fra quelle
    /// fidate: così la lettura non fa comparire il pannello di sistema.
    ///
    /// L'ACL è legata alla firma del codice, quindi regge solo se l'app è
    /// firmata in modo stabile (vedi DEVELOPMENT_TEAM in project.yml): con la
    /// firma ad-hoc, che cambia a ogni build, macOS vede ogni volta un'app
    /// diversa e ricomincia a chiedere.
    ///
    /// API deprecate ma tuttora l'unica strada per il portachiavi classico:
    /// quello moderno ("data protection") richiede entitlement che questo
    /// target, non in sandbox, non può avere.
    private static func selfTrustedAccess() -> SecAccess? {
        var trustedApp: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trustedApp) == errSecSuccess,
              let trustedApp else { return nil }
        var access: SecAccess?
        guard SecAccessCreate("Scrigno" as CFString, [trustedApp] as CFArray, &access) == errSecSuccess else {
            return nil
        }
        return access
    }
    #endif
}
