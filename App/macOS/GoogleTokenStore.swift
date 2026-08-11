import Foundation
import Security

/// Il refresh token (quello che conta davvero: con quello si riottiene
/// l'accesso per sempre) va nel Keychain classico, stessa ricetta di
/// SharedKeychain — un ACL che fida solo di questa app, sul portachiavi
/// "login" e non quello "data protection" (che pretenderebbe entitlement
/// che questo target, senza sandbox, non ha). Il resto (access token,
/// scadenza, id della cartella, data dell'ultimo backup) è tutta roba
/// a vita breve o non sensibile: UserDefaults basta e avanza.
enum GoogleTokenStore {
    private static let service = "com.antonioscirica.hush.googledrive"
    private static let account = "refresh_token"

    static var refreshToken: String? {
        get { read() }
        set {
            if let newValue { store(newValue) } else { delete() }
        }
    }

    static var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "hush.gdrive.accessToken") }
        set { UserDefaults.standard.set(newValue, forKey: "hush.gdrive.accessToken") }
    }

    static var accessTokenExpiry: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "hush.gdrive.accessTokenExpiry")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "hush.gdrive.accessTokenExpiry") }
    }

    static var email: String? {
        get { UserDefaults.standard.string(forKey: "hush.gdrive.email") }
        set { UserDefaults.standard.set(newValue, forKey: "hush.gdrive.email") }
    }

    static var folderID: String? {
        get { UserDefaults.standard.string(forKey: "hush.gdrive.folderID") }
        set { UserDefaults.standard.set(newValue, forKey: "hush.gdrive.folderID") }
    }

    static var lastBackup: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "hush.gdrive.lastBackup")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set { UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "hush.gdrive.lastBackup") }
    }

    static func clear() {
        delete()
        accessToken = nil
        accessTokenExpiry = nil
        folderID = nil
        email = nil
        UserDefaults.standard.removeObject(forKey: "hush.gdrive.lastBackup")
    }

    // MARK: - Keychain (solo il refresh token)

    private static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func store(_ value: String) {
        delete()
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        if let access = selfTrustedAccess() {
            query[kSecAttrAccess as String] = access
        }
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func selfTrustedAccess() -> SecAccess? {
        var trustedApp: SecTrustedApplication?
        guard SecTrustedApplicationCreateFromPath(nil, &trustedApp) == errSecSuccess, let trustedApp else { return nil }
        var access: SecAccess?
        guard SecAccessCreate("Hush" as CFString, [trustedApp] as CFArray, &access) == errSecSuccess else { return nil }
        return access
    }
}
