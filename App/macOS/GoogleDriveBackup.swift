import Foundation

/// Carica i cassetti (già cifrati, così come sono — niente da aggiungere
/// sopra) dentro una cartella dedicata su Drive. La cartella si crea da
/// sola al primo backup; quelli dopo aggiornano gli stessi file invece di
/// accumularne di nuovi.
enum GoogleDriveBackup {
    private static let folderName = "Hush Backup"
    private static let intervallo: TimeInterval = 7 * 86_400

    /// Backup di tutti i progetti, subito.
    static func backupAll() async {
        guard let token = await GoogleDriveAuth.shared.validAccessToken() else { return }
        guard let folderID = await ensureFolder(token: token) else { return }

        for project in VaultFileManager.shared.projects {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: project.path)) else { continue }
            await uploadOrUpdate(fileName: "\(project.name).kdbx", data: data, folderID: folderID, token: token)
        }
        GoogleTokenStore.lastBackup = Date()
    }

    /// Solo se è passata una settimana dall'ultimo — da chiamare a ogni
    /// avvio, costa nulla se non è ancora il momento.
    static func backupIfDue() async {
        guard GoogleDriveAuth.shared.isConnected else { return }
        let ultimo = GoogleTokenStore.lastBackup ?? .distantPast
        guard Date().timeIntervalSince(ultimo) >= intervallo else { return }
        await backupAll()
    }

    // MARK: - Cartella

    private static func ensureFolder(token: String) async -> String? {
        if let saved = GoogleTokenStore.folderID { return saved }

        if let trovata = await findFolder(token: token) {
            GoogleTokenStore.folderID = trovata
            return trovata
        }

        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "name": folderName,
            "mimeType": "application/vnd.google-apps.folder",
        ])
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String
        else { return nil }
        GoogleTokenStore.folderID = id
        return id
    }

    private static func findFolder(token: String) async -> String? {
        let query = "mimeType='application/vnd.google-apps.folder' and name='\(escaped(folderName))' and trashed=false"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [.init(name: "q", value: query), .init(name: "spaces", value: "drive")]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]]
        else { return nil }
        return files.first?["id"] as? String
    }

    // MARK: - File

    private static func uploadOrUpdate(fileName: String, data: Data, folderID: String, token: String) async {
        let existingID = await findFile(named: fileName, in: folderID, token: token)

        var request: URLRequest
        if let existingID {
            request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files/\(existingID)?uploadType=media")!)
            request.httpMethod = "PATCH"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        } else {
            request = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let boundary = "hush-\(UUID().uuidString)"
            request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            let metadata = (try? JSONSerialization.data(withJSONObject: ["name": fileName, "parents": [folderID]])) ?? Data()
            body.append("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
            body.append(metadata)
            body.append("\r\n--\(boundary)\r\nContent-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n--\(boundary)--".data(using: .utf8)!)
            request.httpBody = body
        }

        _ = try? await URLSession.shared.data(for: request)
    }

    private static func findFile(named name: String, in folderID: String, token: String) async -> String? {
        let query = "name='\(escaped(name))' and '\(folderID)' in parents and trashed=false"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [.init(name: "q", value: query)]
        var request = URLRequest(url: comps.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let files = json["files"] as? [[String: Any]]
        else { return nil }
        return files.first?["id"] as? String
    }

    /// Apici singoli nel nome (es. "L'ufficio") romperebbero la query `q`
    /// di Drive se non sfuggiti.
    private static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "\\'")
    }
}
