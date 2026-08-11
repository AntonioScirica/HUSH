import Foundation
import Network
import Security
import VaultCore

/// Token segreto condiviso SOLO fra Hush.app e l'estensione Safari, via
/// Keychain "Data Protection" (l'unica che su macOS supporta i veri
/// `access group` come su iOS — quella classica lega gli elementi all'app
/// che li ha scritti, non a un gruppo). Chi non ha questo token non riceve
/// risposta dal bridge in loopback, chiunque altro sia in ascolto sulla 127.0.0.1.
///
/// Va tenuto IDENTICO a `SafariExtension/Native/BridgeToken.swift`: due copie
/// piccole, invece di far dipendere l'estensione (sandboxata, minimale) da
/// tutto App/Shared.
enum BridgeToken {
    static let accessGroup = "69SHH7M6DY.com.antonioscirica.hush.bridge"
    private static let service = "com.antonioscirica.hush.bridge.token"
    private static let account = "token"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Genera il token la prima volta; le volte dopo riusa quello che c'è.
    @discardableResult
    static func ensureExists() -> String {
        if let existing = read() { return existing }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = Data(bytes).base64EncodedString()

        var query = baseQuery()
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
        return token
    }
}

/// Piccolo server HTTP in loopback: la parte nativa dell'estensione Safari
/// (sandboxata, senza accesso ai file del vault) lo interroga per sapere se
/// Hush è sbloccato e quali voci corrispondono al sito aperto. Gira SOLO
/// mentre Hush è aperto e sbloccato — a scrigno chiuso l'estensione lo trova
/// muto, come deve essere.
@MainActor
final class LocalBridgeServer {
    static let shared = LocalBridgeServer()
    private init() {}

    /// Deve combaciare col PORT in SafariExtension/Native/SafariWebExtensionHandler.swift.
    private static let port: NWEndpoint.Port = 51823

    private var listener: NWListener?

    func start() {
        guard listener == nil else { return }
        BridgeToken.ensureExists()

        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: Self.port)
        guard let listener = try? NWListener(using: params) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let range = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(to: buffer[..<range.lowerBound], on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(to headerData: Data, on connection: NWConnection) {
        let text = String(data: headerData, encoding: .utf8) ?? ""
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { connection.cancel(); return }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { connection.cancel(); return }
        let path = parts[1]

        var token: String?
        for line in lines.dropFirst() where line.lowercased().hasPrefix("x-hush-token:") {
            token = line.dropFirst("x-hush-token:".count).trimmingCharacters(in: .whitespaces)
        }

        write(json: handleRequest(path: path, token: token), to: connection)
    }

    private func handleRequest(path: String, token: String?) -> [String: Any] {
        guard let token, let expected = BridgeToken.read(), token == expected else {
            return ["error": "forbidden"]
        }
        guard let components = URLComponents(string: "http://x" + path) else {
            return ["error": "bad_request"]
        }

        switch components.path {
        case "/status":
            return [
                "unlocked": MasterKey.isUnlocked,
                "hasVault": !VaultFileManager.shared.projects.isEmpty,
            ]

        case "/matches":
            guard MasterKey.isUnlocked else { return ["error": "locked"] }
            let host = (components.queryItems?.first(where: { $0.name == "host" })?.value ?? "").lowercased()
            var found: [[String: String]] = []
            for project in VaultFileManager.shared.projects {
                for entry in VaultLibrary.shared.entries(of: project) {
                    guard host.isEmpty || HostMatch.matches(entryURL: entry.url, entryTitle: entry.title, host: host) else { continue }
                    found.append([
                        "title": entry.title,
                        "username": entry.username,
                        "password": entry.password,
                        "projectName": project.name,
                    ])
                }
            }
            return ["entries": found]

        default:
            return ["error": "not_found"]
        }
    }

    private func write(json: [String: Any], to connection: NWConnection) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\n".utf8)
        response.append(Data("Content-Type: application/json\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
