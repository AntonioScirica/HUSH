import Foundation
import Security

/// Copia gemella di App/macOS/LocalBridge.swift (solo lettura, qui): questo
/// target è volutamente piccolo e sandboxato, senza dipendere da tutto
/// App/Shared. Le due copie DEVONO restare identiche in `accessGroup`,
/// `service` e `account`, o il token letto qui non combacerà mai con quello
/// scritto da Hush.app.
enum BridgeToken {
    static let accessGroup = "69SHH7M6DY.com.antonioscirica.hush.bridge"
    private static let service = "com.antonioscirica.hush.bridge.token"
    private static let account = "token"

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
