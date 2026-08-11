import Foundation
import Network
import AppKit

/// Login con Google via il browser di default (non una webview dentro
/// Hush: mai vedere una password in un posto che non è Google stesso) e un
/// piccolo server in loopback che aspetta il ritorno — è il flusso che
/// Google stesso documenta per le app "Desktop": un client OAuth di quel
/// tipo accetta come redirect_uri solo `http://127.0.0.1:<qualunque porta>`,
/// non uno schema personalizzato. Scope minimo — `drive.file` — Hush vede
/// solo i file che crea lui, non il resto del Drive.
final class GoogleDriveAuth {
    static let shared = GoogleDriveAuth()
    private init() {}

    private static let clientID = "312743210385-gmdig49g42fjr2uigln7b925f1udvq10.apps.googleusercontent.com"
    private static let clientSecret = "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"
    private static let scope = "https://www.googleapis.com/auth/drive.file"

    private var listener: NWListener?
    private var porta: UInt16 = 0

    var isConnected: Bool { GoogleTokenStore.refreshToken != nil }
    var accountEmail: String? { GoogleTokenStore.email }

    func connect(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let listener = try? NWListener(using: .tcp, on: .any) else {
            completion(.failure(NSError(domain: "GoogleDrive", code: 0, userInfo: [NSLocalizedDescriptionKey: "Non riesco ad aprire una porta locale per il login."])))
            return
        }
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            guard case .ready = state, let port = listener.port?.rawValue else { return }
            self?.porta = port
            self?.apriBrowser(porta: port)
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.gestisciRitorno(connection, completion: completion)
        }
        listener.start(queue: .main)
    }

    private func apriBrowser(porta: UInt16) {
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: "http://127.0.0.1:\(porta)/oauth2redirect"),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "access_type", value: "offline"),
            // sempre il consenso, anche se già dato altre volte: è l'unico
            // modo per essere certi che torni un refresh_token, la prima
            // volta soltanto — dopo, Google lo dà per scontato e tace
            .init(name: "prompt", value: "consent"),
        ]
        NSWorkspace.shared.open(comps.url!)
    }

    private func gestisciRitorno(_ connection: NWConnection, completion: @escaping (Result<Void, Error>) -> Void) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, let data,
                  let text = String(data: data, encoding: .utf8),
                  let requestLine = text.components(separatedBy: "\r\n").first,
                  let path = requestLine.components(separatedBy: " ").dropFirst().first
            else {
                connection.cancel()
                return
            }

            self.rispondi(connection)
            self.listener?.cancel()
            self.listener = nil

            let comps = URLComponents(string: "http://x\(path)")
            guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value else {
                let messaggio = comps?.queryItems?.first(where: { $0.name == "error" })?.value ?? "nessun codice ricevuto"
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GoogleDrive", code: 1, userInfo: [NSLocalizedDescriptionKey: "Login annullato (\(messaggio))."])))
                }
                return
            }
            self.exchangeCode(code, porta: self.porta, completion: completion)
        }
    }

    /// Una paginetta di cortesia: l'utente torna su Hush da sé, ma se resta
    /// sulla scheda del browser non deve vedere un errore.
    private func rispondi(_ connection: NWConnection) {
        let corpo = "<html><body style=\"font-family:-apple-system;padding:40px;color:#222\">Fatto — torna pure su Hush.</body></html>"
        let risposta = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(corpo.utf8.count)\r\nConnection: close\r\n\r\n\(corpo)"
        connection.send(content: Data(risposta.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    func disconnect() {
        GoogleTokenStore.clear()
    }

    /// Token pronto all'uso, rinfrescato da sé se scaduto. `nil` se non
    /// c'è mai stato un collegamento o Google l'ha revocato.
    func validAccessToken() async -> String? {
        if let token = GoogleTokenStore.accessToken,
           let expiry = GoogleTokenStore.accessTokenExpiry,
           expiry > Date() {
            return token
        }
        guard let refreshToken = GoogleTokenStore.refreshToken else { return nil }
        return await refreshAccessToken(refreshToken: refreshToken)
    }

    // MARK: - Scambio codice / rinnovo

    private func exchangeCode(_ code: String, porta: UInt16, completion: @escaping (Result<Void, Error>) -> Void) {
        postToken(body: [
            "client_id": Self.clientID,
            "client_secret": Self.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": "http://127.0.0.1:\(porta)/oauth2redirect",
        ]) { [weak self] json in
            guard let self, let json,
                  let refreshToken = json["refresh_token"] as? String,
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? Double
            else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GoogleDrive", code: 2, userInfo: [NSLocalizedDescriptionKey: "Google non ha restituito un token valido."])))
                }
                return
            }
            GoogleTokenStore.refreshToken = refreshToken
            GoogleTokenStore.accessToken = accessToken
            GoogleTokenStore.accessTokenExpiry = Date().addingTimeInterval(expiresIn - 60)

            self.fetchEmail(accessToken: accessToken) { email in
                GoogleTokenStore.email = email
                DispatchQueue.main.async { completion(.success(())) }
            }
        }
    }

    private func refreshAccessToken(refreshToken: String) async -> String? {
        await withCheckedContinuation { cont in
            postToken(body: [
                "client_id": Self.clientID,
                "client_secret": Self.clientSecret,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token",
            ]) { json in
                guard let json,
                      let accessToken = json["access_token"] as? String,
                      let expiresIn = json["expires_in"] as? Double
                else { cont.resume(returning: nil); return }
                GoogleTokenStore.accessToken = accessToken
                GoogleTokenStore.accessTokenExpiry = Date().addingTimeInterval(expiresIn - 60)
                cont.resume(returning: accessToken)
            }
        }
    }

    private func postToken(body: [String: String], completion: @escaping ([String: Any]?) -> Void) {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            completion(json)
        }.resume()
    }

    private func fetchEmail(accessToken: String, completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            completion(json?["email"] as? String)
        }.resume()
    }
}
