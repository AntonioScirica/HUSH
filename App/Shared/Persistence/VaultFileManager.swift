import Foundation

enum VaultFileError: Error, LocalizedError {
    case noFileChosen
    case appGroupUnavailable
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .noFileChosen: return "Nessun file del vault selezionato."
        case .appGroupUnavailable: return "Impossibile accedere allo spazio condiviso dell'app."
        case .accessDenied: return "Accesso al file negato."
        }
    }
}

/// Identificatore dell'App Group condiviso tra l'app iOS e l'estensione
/// AutoFill — deve combaciare con quanto impostato in project.yml e in
/// Signing & Capabilities per entrambi i target.
enum SharedGroup {
    static let id = "group.com.antonioscirica.scrigno"
}

#if os(iOS)
import Foundation

/// Su iOS, l'app vive in un sandbox: per continuare ad accedere a un file
/// scelto dall'utente (tipicamente su iCloud Drive) tra un avvio e l'altro —
/// e per farlo accedere anche all'estensione AutoFill, che è un processo
/// separato — usiamo un security-scoped bookmark salvato nel contenitore
/// dell'App Group condiviso.
final class VaultFileManager {
    static let shared = VaultFileManager()
    private init() {}

    private var bookmarkURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedGroup.id)?
            .appendingPathComponent("vault-bookmark.data")
    }

    struct Project: Codable, Identifiable, Equatable {
        let name: String
        let path: String
        var icon: String?        // nome SF Symbol; nil = nessun post-it
        var noteColor: String?   // colore del post-it (esadecimale)
        var id: String { path }

        init(name: String, path: String, icon: String? = nil, noteColor: String? = nil) {
            self.name = name
            self.path = path
            self.icon = icon
            self.noteColor = noteColor
        }
    }

    // ponytail: home multi-progetto sviluppata per macOS; su iOS il bookmark
    // security-scoped resta singolo, quindi selectProject non riapre ancora
    // il file giusto — da estendere a un bookmark per progetto quando serve.
    var projects: [Project] {
        guard let data = UserDefaults.standard.data(forKey: "vaultProjects"),
              let list = try? JSONDecoder().decode([Project].self, from: data) else { return [] }
        return list
    }

    func addProject(name: String, url: URL) throws {
        var list = projects
        if !list.contains(where: { $0.path == url.path }) {
            list.append(Project(name: name, path: url.path))
            if let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(data, forKey: "vaultProjects")
            }
        }
        try rememberVaultLocation(url)
    }

    func selectProject(_ project: Project) throws {
        try rememberVaultLocation(URL(fileURLWithPath: project.path))
    }

    var hasVault: Bool {
        (try? resolveURL()) != nil
    }

    /// Da chiamare quando l'utente sceglie/crea il file del vault (es. tramite
    /// un file importer/exporter di SwiftUI che restituisce un URL con accesso
    /// security-scoped già attivo).
    func rememberVaultLocation(_ url: URL) throws {
        guard let bookmarkURL else { throw VaultFileError.appGroupUnavailable }
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        try bookmark.write(to: bookmarkURL, options: .atomic)
    }

    private func resolveURL() throws -> URL {
        guard let bookmarkURL, let data = try? Data(contentsOf: bookmarkURL) else {
            throw VaultFileError.noFileChosen
        }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        return url
    }

    func readVault() throws -> [UInt8] {
        let url = try resolveURL()
        guard url.startAccessingSecurityScopedResource() else { throw VaultFileError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        return Array(try Data(contentsOf: url))
    }

    func writeVault(_ bytes: [UInt8]) throws {
        let url = try resolveURL()
        guard url.startAccessingSecurityScopedResource() else { throw VaultFileError.accessDenied }
        defer { url.stopAccessingSecurityScopedResource() }
        try Data(bytes).write(to: url, options: .atomic)
    }

    var vaultDisplayName: String {
        (try? resolveURL().lastPathComponent) ?? "Vault"
    }
}
#endif

#if os(macOS)
import Foundation

/// Su macOS l'app non è in sandbox (nessuna entitlement configurata in
/// project.yml), quindi l'accesso al file è diretto: basta ricordarsi il
/// percorso scelto dall'utente tra un avvio e l'altro.
final class VaultFileManager {
    static let shared = VaultFileManager()
    private init() {}

    private let defaultsKey = "vaultFilePath"
    private let projectsKey = "vaultProjects"

    struct Project: Codable, Identifiable, Equatable {
        let name: String
        let path: String
        var icon: String?        // nome SF Symbol; nil = nessun post-it
        var noteColor: String?   // colore del post-it (esadecimale)
        var id: String { path }

        init(name: String, path: String, icon: String? = nil, noteColor: String? = nil) {
            self.name = name
            self.path = path
            self.icon = icon
            self.noteColor = noteColor
        }
    }

    /// Progetti (vault separati) conosciuti — elenco per la home a "scatola".
    var projects: [Project] {
        guard let data = UserDefaults.standard.data(forKey: projectsKey),
              let list = try? JSONDecoder().decode([Project].self, from: data) else { return [] }
        return list
    }

    /// Registra un progetto (se non già presente) e lo imposta come corrente.
    func addProject(name: String, url: URL, icon: String? = nil, noteColor: String? = nil) throws {
        var list = projects
        if !list.contains(where: { $0.path == url.path }) {
            list.append(Project(name: name, path: url.path, icon: icon, noteColor: noteColor))
            if let data = try? JSONEncoder().encode(list) {
                UserDefaults.standard.set(data, forKey: projectsKey)
            }
        }
        try rememberVaultLocation(url)
    }

    /// Aggiorna nome, icona e colore del post-it di un progetto già esistente.
    func updateProject(id: String, name: String, icon: String?, noteColor: String?) {
        var list = projects
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i] = Project(name: name, path: list[i].path, icon: icon, noteColor: noteColor)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: projectsKey)
        }
    }

    /// Rimuove il progetto dall'elenco e cancella il suo file .kdbx dal disco.
    func deleteProject(id: String) {
        var list = projects
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let path = list[i].path
        list.remove(at: i)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: projectsKey)
        }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        if UserDefaults.standard.string(forKey: defaultsKey) == path {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    /// Cartella dell'app per i vault creati da qui — niente dialog di
    /// sistema: si salva e basta, come gli altri passaggi già snelliti.
    var projectsDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scrigno", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Cartella per gli allegati dei documenti — file leggeri copiati qui
    /// così restano raggiungibili anche se l'originale viene spostato/cancellato.
    var attachmentsDirectory: URL {
        let dir = projectsDirectory.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Copia il file scelto negli allegati dell'app, con un nome univoco che
    /// mantiene comunque leggibile il nome originale.
    func storeAttachment(from sourceURL: URL) throws -> URL {
        let unique = "\(UUID().uuidString)-\(sourceURL.lastPathComponent)"
        let dest = attachmentsDirectory.appendingPathComponent(unique)
        try FileManager.default.copyItem(at: sourceURL, to: dest)
        return dest
    }

    /// Percorso libero per un nuovo progetto con questo nome (aggiunge un
    /// suffisso numerico se il file esiste già).
    func freeProjectURL(named name: String) -> URL {
        let base = name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        let safe = base.isEmpty ? "progetto" : base
        var url = projectsDirectory.appendingPathComponent("\(safe).kdbx")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = projectsDirectory.appendingPathComponent("\(safe)-\(n).kdbx")
            n += 1
        }
        return url
    }

    func selectProject(_ project: Project) throws {
        try rememberVaultLocation(URL(fileURLWithPath: project.path))
    }

    var hasVault: Bool {
        UserDefaults.standard.string(forKey: defaultsKey) != nil
    }

    func rememberVaultLocation(_ url: URL) throws {
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
    }

    private func resolveURL() throws -> URL {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else {
            throw VaultFileError.noFileChosen
        }
        return URL(fileURLWithPath: path)
    }

    func readVault() throws -> [UInt8] {
        Array(try Data(contentsOf: try resolveURL()))
    }

    func writeVault(_ bytes: [UInt8]) throws {
        try Data(bytes).write(to: try resolveURL(), options: .atomic)
    }

    var vaultDisplayName: String {
        (try? resolveURL().lastPathComponent) ?? "Vault"
    }
}
#endif
