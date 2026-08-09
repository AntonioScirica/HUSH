import Foundation

/// Una voce letta da un file esportato da un altro gestore di password.
struct ImportedEntry {
    var title: String
    var username: String
    var password: String
    var url: String
    var notes: String
}

/// Voci lette durante l'onboarding e in attesa di finire in un progetto.
///
/// L'onboarding non ha ancora un vault dove metterle — quello nasce quando si
/// entra — quindi restano qui in mezzo per il tempo di un passaggio, e chi le
/// prende le cancella.
enum PendingImport {
    static var projectName: String = "importate"
    static var entries: [ImportedEntry] = []

    static var isEmpty: Bool { entries.isEmpty }

    static func clear() {
        entries = []
        projectName = "importate"
    }
}

/// Lettura dei CSV esportati dagli altri gestori.
///
/// Il CSV è il minimo comun denominatore: 1Password, Bitwarden, LastPass,
/// Chrome e Safari lo esportano tutti, solo con intestazioni diverse. Invece
/// di un lettore per ciascuno, si cercano le colonne per nome fra i sinonimi
/// noti — chi non ha una colonna semplicemente la lascia vuota.
enum CSVImport {
    enum Failure: Error, LocalizedError {
        case unreadable
        case noColumns
        case noRows

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Non riesco a leggere il file."
            case .noColumns:  return "Non trovo le colonne del titolo e della password."
            case .noRows:     return "Il file non contiene voci."
            }
        }
    }

    private static let titleKeys = ["title", "name", "account", "item name", "display name"]
    private static let userKeys = ["username", "user", "login_username", "login name", "user name", "email", "e-mail"]
    private static let passwordKeys = ["password", "login_password", "pass"]
    private static let urlKeys = ["url", "urls", "website", "web site", "login_uri", "login_url", "uri"]
    private static let noteKeys = ["notes", "note", "extra", "comments", "comment"]

    static func parse(contentsOf url: URL) throws -> [ImportedEntry] {
        guard let text = readText(at: url) else { throw Failure.unreadable }
        let rows = rows(in: text)
        guard let header = rows.first else { throw Failure.noRows }

        let keys = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let titleIdx = index(of: titleKeys, in: keys)
        let passIdx = index(of: passwordKeys, in: keys)
        guard titleIdx != nil || passIdx != nil else { throw Failure.noColumns }

        let userIdx = index(of: userKeys, in: keys)
        let urlIdx = index(of: urlKeys, in: keys)
        let noteIdx = index(of: noteKeys, in: keys)

        func field(_ row: [String], _ idx: Int?) -> String {
            guard let idx, idx < row.count else { return "" }
            return row[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let entries = rows.dropFirst().compactMap { row -> ImportedEntry? in
            guard row.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return nil }
            let title = field(row, titleIdx)
            let url = field(row, urlIdx)
            // senza titolo si ripiega sul dominio: meglio "netflix.com" che
            // una riga senza nome nel cassetto
            let name = title.isEmpty ? host(of: url) : title
            guard !name.isEmpty else { return nil }
            return ImportedEntry(
                title: name,
                username: field(row, userIdx),
                password: field(row, passIdx),
                url: url,
                notes: field(row, noteIdx)
            )
        }
        guard !entries.isEmpty else { throw Failure.noRows }
        return entries
    }

    private static func index(of candidates: [String], in header: [String]) -> Int? {
        for key in candidates {
            if let i = header.firstIndex(of: key) { return i }
        }
        return nil
    }

    private static func host(of url: String) -> String {
        guard let comps = URLComponents(string: url), let host = comps.host else { return "" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// I CSV esportati non sono sempre UTF-8: Windows e vecchi export usano
    /// spesso Latin-1, e leggerli come UTF-8 restituisce nil.
    private static func readText(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(data: data, encoding: .isoLatin1)
    }

    /// Divide il CSV in righe di campi, rispettando le virgolette: dentro le
    /// virgolette virgole e a capo fanno parte del valore (le note lunghe di
    /// 1Password vanno spesso a capo), e `""` è una virgoletta letterale.
    static func rows(in text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()
        var pending: Character?

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let ch = pending ?? iterator.next() {
            pending = nil
            if inQuotes {
                if ch == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { inQuotes = false; pending = next }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
                continue
            }
            switch ch {
            case "\"": inQuotes = true
            case ",":  endField()
            case "\n": endRow()
            case "\r": break   // CRLF: il \n che segue chiude la riga
            default:   field.append(ch)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
}
