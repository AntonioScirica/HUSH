import SafariServices

/// Ponte fra il JS dell'estensione (background.js) e Hush.app: questo
/// processo è sandboxato e non tocca mai un file .kdbx, gira solo da inoltro
/// verso il piccolo server in loopback che Hush.app apre mentre è sbloccato
/// (vedi App/macOS/LocalBridge.swift).
class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    /// Deve combaciare col PORT in App/macOS/LocalBridge.swift.
    private static let port = 51823

    func beginRequest(with context: NSExtensionContext) {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let type = message["type"] as? String
        else {
            complete(context, with: ["error": "bad_request"])
            return
        }

        switch type {
        case "status":
            call(context, path: "/status")
        case "matches":
            let host = (message["host"] as? String) ?? ""
            let escaped = host.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            call(context, path: "/matches?host=\(escaped)")
        case "search":
            let query = (message["query"] as? String) ?? ""
            let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            call(context, path: "/search?q=\(escaped)")
        default:
            complete(context, with: ["error": "unknown_type"])
        }
    }

    private func call(_ context: NSExtensionContext, path: String) {
        guard let token = BridgeToken.read(),
              let url = URL(string: "http://127.0.0.1:\(Self.port)\(path)")
        else {
            complete(context, with: ["error": "unreachable"])
            return
        }
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "X-Hush-Token")
        request.timeoutInterval = 3

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }
            guard let data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.complete(context, with: ["error": "unreachable"])
                return
            }
            self.complete(context, with: json)
        }.resume()
    }

    private func complete(_ context: NSExtensionContext, with dict: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: dict]
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
