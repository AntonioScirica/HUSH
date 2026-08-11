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

/// L'accesso ai file è diretto: su macOS l'app non è in sandbox, su iOS i
/// vault vivono nel contenitore dell'app (condiviso con l'estensione
/// AutoFill), quindi in entrambi i casi basta ricordarsi il percorso.
final class VaultFileManager {
    static let shared = VaultFileManager()
    private init() {}

    private let defaultsKey = "vaultFilePath"
    private let projectsKey = "vaultProjects"

    /// Su iOS l'elenco progetti va letto/scritto nel gruppo condiviso: app e
    /// estensione AutoFill sono processi separati, ciascuno con un proprio
    /// `UserDefaults.standard` — senza il suite del gruppo l'estensione
    /// vedrebbe sempre zero progetti. Su macOS non c'è App Group (il target
    /// non è in sandbox), quindi resta `.standard` come sempre.
    private var defaults: UserDefaults {
        #if os(iOS)
        UserDefaults(suiteName: SharedGroup.id) ?? .standard
        #else
        .standard
        #endif
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

    /// Progetti (vault separati) conosciuti — elenco per la home a "scatola".
    var projects: [Project] {
        guard let data = defaults.data(forKey: projectsKey),
              let list = try? JSONDecoder().decode([Project].self, from: data) else { return [] }
        return list
    }

    /// Registra un progetto (se non già presente) e lo imposta come corrente.
    func addProject(name: String, url: URL, icon: String? = nil, noteColor: String? = nil) throws {
        var list = projects
        if !list.contains(where: { $0.path == url.path }) {
            list.append(Project(name: name, path: url.path, icon: icon, noteColor: noteColor))
            if let data = try? JSONEncoder().encode(list) {
                defaults.set(data, forKey: projectsKey)
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
            defaults.set(data, forKey: projectsKey)
        }
    }

    /// Rimuove il progetto dall'elenco e cancella il suo file .kdbx dal disco.
    func deleteProject(id: String) {
        var list = projects
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        let path = list[i].path
        list.remove(at: i)
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: projectsKey)
        }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
        if defaults.string(forKey: defaultsKey) == path {
            defaults.removeObject(forKey: defaultsKey)
        }
    }

    /// Cartella dell'app per i vault creati da qui — niente dialog di
    /// sistema: si salva e basta, come gli altri passaggi già snelliti.
    var projectsDirectory: URL {
        let dir = cartellaScelta ?? Self.cartellaPredefinita
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Dove finiscono i cassetti se non scegli tu.
    static var cartellaPredefinita: URL {
        #if os(macOS)
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hush", isDirectory: true)
        #else
        // il contenitore del gruppo, così l'estensione AutoFill legge gli
        // stessi file; se il gruppo non è configurato si ripiega sui Documenti
        let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedGroup.id)
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Hush", isDirectory: true)
        #endif
    }

    private let cartellaKey = "scrigno.cartellaCassetti"

    /// La cartella scelta dall'utente, se ne ha scelta una.
    ///
    /// Serve a chi vuole tenere i cassetti in una cartella che si sincronizza
    /// da sola: da lì li ritrova sull'altro computer senza che Hush parli con
    /// nessuno. Se la cartella sparisce (disco staccato, servizio scollegato)
    /// si torna a quella predefinita invece di piantarsi.
    var cartellaScelta: URL? {
        guard let path = defaults.string(forKey: cartellaKey) else { return nil }
        var cartella = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &cartella), cartella.boolValue
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Sposta tutto quello che c'è (cassetti, allegati, chiave di recupero)
    /// nella cartella nuova e aggiorna i percorsi che ogni progetto si porta
    /// dietro. Chi chiama deve aver già salvato e chiuso i cassetti aperti.
    func spostaCartella(in nuova: URL) throws {
        let fm = FileManager.default
        let vecchia = projectsDirectory
        guard vecchia.standardizedFileURL != nuova.standardizedFileURL else { return }
        try fm.createDirectory(at: nuova, withIntermediateDirectories: true)

        for file in (try? fm.contentsOfDirectory(at: vecchia, includingPropertiesForKeys: nil)) ?? [] {
            let destinazione = nuova.appendingPathComponent(file.lastPathComponent)
            if fm.fileExists(atPath: destinazione.path) {
                // già lì: non si sovrascrive niente, il file vecchio resta dov'è
                continue
            }
            try fm.moveItem(at: file, to: destinazione)
        }

        defaults.set(nuova.path, forKey: cartellaKey)
        riscriviPercorsi(da: vecchia, a: nuova)
    }

    /// I progetti salvano il percorso completo del loro file: spostata la
    /// cartella, senza questo passaggio punterebbero nel vuoto.
    private func riscriviPercorsi(da vecchia: URL, a nuova: URL) {
        let d = defaults
        func aggiorna(_ path: String) -> String {
            let file = URL(fileURLWithPath: path)
            guard file.deletingLastPathComponent().standardizedFileURL == vecchia.standardizedFileURL
            else { return path }
            return nuova.appendingPathComponent(file.lastPathComponent).path
        }
        let aggiornati = projects.map {
            Project(name: $0.name, path: aggiorna($0.path), icon: $0.icon, noteColor: $0.noteColor)
        }
        if let data = try? JSONEncoder().encode(aggiornati) {
            d.set(data, forKey: projectsKey)
        }
        if let corrente = d.string(forKey: defaultsKey) {
            d.set(aggiorna(corrente), forKey: defaultsKey)
        }
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

    /// Percorso del vault "corrente" (l'ultimo selezionato).
    var currentPath: String? {
        defaults.string(forKey: defaultsKey)
    }

    var hasVault: Bool {
        defaults.string(forKey: defaultsKey) != nil
    }

    func rememberVaultLocation(_ url: URL) throws {
        defaults.set(url.path, forKey: defaultsKey)
    }

    private func resolveURL() throws -> URL {
        guard let path = defaults.string(forKey: defaultsKey) else {
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
