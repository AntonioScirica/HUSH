import Foundation

/// Importazione dagli archivi `.1pux` di 1Password.
///
/// Un `.1pux` è uno zip: dentro c'è `export.data`, un JSON con tutti gli
/// account, i vault e le voci, e una cartella `files` con gli allegati.
///
/// Ogni **vault** di 1Password diventa un **cassetto** di Scrigno: è la stessa
/// idea di divisione, e chi arriva da lì ritrova la propria organizzazione
/// invece di un unico mucchio da risistemare a mano.
enum OnePasswordImport {
    enum Failure: Error, LocalizedError {
        case notAnArchive
        case noData

        var errorDescription: String? {
            switch self {
            case .notAnArchive: return "Non riesco ad aprire questo .1pux."
            case .noData:       return "L'archivio non contiene voci."
            }
        }
    }

    /// Un cassetto pronto da creare, con dentro le sue voci.
    struct Vault {
        var name: String
        var entries: [ImportedEntry]
        /// Voci che non sono semplici accessi: carte, identità, note.
        var details: [(title: String, kind: String, fields: [(label: String, value: String)])]
    }

    // MARK: - Lettura

    static func read(_ archive: URL) throws -> [Vault] {
        let unpacked = try unzip(archive)
        defer { try? FileManager.default.removeItem(at: unpacked) }

        let dataURL = unpacked.appendingPathComponent("export.data")
        guard let raw = try? Data(contentsOf: dataURL),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any]
        else { throw Failure.notAnArchive }

        let accounts = json["accounts"] as? [[String: Any]] ?? []
        var vaults: [Vault] = []

        for account in accounts {
            for rawVault in account["vaults"] as? [[String: Any]] ?? [] {
                let attrs = rawVault["attrs"] as? [String: Any] ?? [:]
                let name = (attrs["name"] as? String) ?? "senza nome"
                var vault = Vault(name: name, entries: [], details: [])

                for item in rawVault["items"] as? [[String: Any]] ?? [] {
                    // Nel cestino di 1Password c'è roba buttata via: portarsela
                    // dietro vorrebbe dire riempire i cassetti di scarti.
                    if (item["state"] as? String) == "archived" { continue }
                    parse(item, into: &vault)
                }

                if !vault.entries.isEmpty || !vault.details.isEmpty {
                    vaults.append(vault)
                }
            }
        }

        guard !vaults.isEmpty else { throw Failure.noData }
        return vaults
    }

    // MARK: - Traduzione di una voce

    /// Categorie di 1Password, per numero. Le altre finiscono fra le note.
    private static func kind(for category: String) -> String {
        switch category {
        case "001": return "login"
        case "002": return "card"
        case "004": return "identity"
        case "005": return "password"
        case "003": return "secureNote"
        default:    return "secureNote"
        }
    }

    private static func parse(_ item: [String: Any], into vault: inout Vault) {
        let overview = item["overview"] as? [String: Any] ?? [:]
        let details = item["details"] as? [String: Any] ?? [:]
        let title = (overview["title"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !title.isEmpty else { return }

        let category = (item["categoryUuid"] as? String) ?? "003"
        let url = (overview["url"] as? String) ?? ""

        // campi di accesso: utente e password stanno qui
        var user = "", password = ""
        for field in details["loginFields"] as? [[String: Any]] ?? [] {
            let designation = (field["designation"] as? String) ?? ""
            let value = (field["value"] as? String) ?? ""
            if designation == "username", user.isEmpty { user = value }
            if designation == "password", password.isEmpty { password = value }
        }

        // tutto il resto sta nelle sezioni, in coppie titolo/valore
        var extra: [(label: String, value: String)] = []
        for section in details["sections"] as? [[String: Any]] ?? [] {
            for field in section["fields"] as? [[String: Any]] ?? [] {
                let label = (field["title"] as? String) ?? "campo"
                guard let value = readValue(field["value"]) , !value.isEmpty else { continue }
                extra.append((label: label, value: value))
            }
        }

        // le note libere di 1Password
        let notes = (details["notesPlain"] as? String) ?? ""

        switch kind(for: category) {
        case "login", "password":
            vault.entries.append(ImportedEntry(
                title: title, username: user, password: password, url: url, notes: notes
            ))
            // i campi extra di un accesso non vanno persi
            if !extra.isEmpty {
                vault.details.append((title: title, kind: "extra", fields: extra))
            }
        case let altro:
            var fields = extra
            if !notes.isEmpty { fields.append((label: "note", value: notes)) }
            if !url.isEmpty { fields.append((label: "url", value: url)) }
            guard !fields.isEmpty else { return }
            vault.details.append((title: title, kind: altro, fields: fields))
        }
    }

    /// Il valore di un campo è un oggetto con una chiave sola, che dice anche
    /// di che tipo è: `string`, `concealed`, `date`, `email`...
    private static func readValue(_ raw: Any?) -> String? {
        guard let dict = raw as? [String: Any] else { return raw as? String }
        for (_, v) in dict {
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            if let sub = v as? [String: Any] {
                // es. indirizzo: un oggetto con via, città, paese
                let parti = sub.values.compactMap { $0 as? String }.filter { !$0.isEmpty }
                if !parti.isEmpty { return parti.joined(separator: ", ") }
            }
        }
        return nil
    }

    // MARK: - Zip

    /// Un `.1pux` è uno zip con un'estensione sua: si scompatta con lo
    /// strumento di sistema, che c'è su ogni Mac.
    private static func unzip(_ archive: URL) throws -> URL {
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrigno-1pux-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", "-q", archive.path, "-d", dest.path]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else { throw Failure.notAnArchive }
        return dest
    }
}
