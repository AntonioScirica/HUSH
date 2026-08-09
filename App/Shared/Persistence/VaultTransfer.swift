import Foundation
import AppKit
import VaultCore

/// Trasloco dello scrigno da un computer all'altro.
///
/// Serve quando si stacca la licenza da un Mac per attaccarla a un altro: la
/// licenza da sola non basta, dall'altra parte servono anche i cassetti.
///
/// Quel che esce è una cartella con dentro i `.kdbx` così come sono — già
/// cifrati con la master password, quindi il trasloco non li espone mai in
/// chiaro, nemmeno passando da una chiavetta o da un disco condiviso — più un
/// piccolo indice con nomi, icone e colori dei post-it, che nei file non ci
/// stanno e altrimenti si perderebbero.
///
/// La chiave di recupero NON viene esportata: è legata a questo computer per
/// scelta, e portarsela in giro insieme ai vault vorrebbe dire mettere la
/// serratura e la chiave nella stessa scatola.
enum VaultTransfer {
    static let manifestName = "scrigno-progetti.json"

    private struct Manifest: Codable {
        var progetti: [VaultFileManager.Project]
        var esportato: Double
    }

    // MARK: - Esportazione

    enum Failure: Error, LocalizedError {
        case exportingOntoItself

        var errorDescription: String? {
            switch self {
            case .exportingOntoItself:
                return "Quella è la cartella dove Scrigno tiene i vault: scegline un'altra."
            }
        }
    }

    /// Copia tutti i vault e l'indice nella cartella scelta.
    @discardableResult
    static func export(to folder: URL) throws -> Int {
        let projects = VaultFileManager.shared.projects
        let fm = FileManager.default

        // Esportare dentro alla cartella dei vault vorrebbe dire copiare ogni
        // file su sé stesso: sotto c'è una rimozione del file di destinazione,
        // che qui cancellerebbe l'originale. Meglio fermarsi prima.
        guard folder.standardizedFileURL != VaultFileManager.shared.projectsDirectory.standardizedFileURL else {
            throw Failure.exportingOntoItself
        }

        for project in projects {
            let source = URL(fileURLWithPath: project.path)
            guard fm.fileExists(atPath: source.path) else { continue }
            let dest = folder.appendingPathComponent(source.lastPathComponent)
            guard dest.standardizedFileURL != source.standardizedFileURL else { continue }
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        }

        let manifest = Manifest(progetti: projects, esportato: Date().timeIntervalSince1970)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        return projects.count
    }

    // MARK: - Anteprima

    /// Cosa c'è dentro a un file da importare, prima di importarlo.
    struct Preview: Identifiable {
        let id = UUID()
        var file: URL
        var name: String
        var icon: String?
        var noteColor: String?
        /// Titoli delle voci, se il vault si è aperto.
        var entries: [String] = []
        /// Perché non si è potuto leggere, se non si è potuto.
        var problem: String?
        /// Password con cui si è riusciti ad aprirlo, se diversa da quella
        /// dello scrigno: all'importazione il file viene ricifrato con la
        /// nostra, se no resterebbe un cassetto che non si apre.
        var foreignPassword: String?

        var isReadable: Bool { problem == nil }
    }

    /// Guarda dentro ai file scelti senza toccare niente.
    ///
    /// Serve soprattutto a scoprire subito il caso brutto: un vault che arriva
    /// da un altro computer può essere cifrato con un'ALTRA master password.
    /// Importato alla cieca diventerebbe un cassetto che non si apre, e uno se
    /// ne accorgerebbe solo dopo. Meglio dirlo prima.
    static func inspect(_ selection: [URL]) -> [Preview] {
        let (files, manifest) = collect(selection)
        return files.map { file in
            let original = manifest?.progetti.first {
                URL(fileURLWithPath: $0.path).lastPathComponent == file.lastPathComponent
            }
            var preview = Preview(
                file: file,
                name: original?.name ?? file.deletingPathExtension().lastPathComponent,
                icon: original?.icon,
                noteColor: original?.noteColor
            )
            // già dentro allo scrigno: reimportarlo creerebbe un doppione
            if VaultFileManager.shared.projects.contains(where: {
                URL(fileURLWithPath: $0.path).standardizedFileURL == file.standardizedFileURL
            }) {
                preview.problem = "già nello scrigno"
                return preview
            }
            guard let key = MasterKey.session else {
                preview.problem = "scrigno bloccato"
                return preview
            }
            do {
                let bytes = Array(try Data(contentsOf: file))
                let db = try Kdbx4.open(data: bytes, password: key)
                preview.entries = db.allEntries.map(\.title)
            } catch {
                preview.problem = "cifrato con un'altra password"
            }
            return preview
        }
    }

    // MARK: - Importazione

    /// Rimette dentro a questo computer i vault esportati altrove.
    ///
    /// Accetta indifferentemente la cartella dell'esportazione o i singoli
    /// `.kdbx` scelti a mano: chi importa non deve indovinare cosa gli si
    /// aspetta.
    ///
    /// I percorsi dell'altro Mac non valgono qui: ogni file viene ricollocato
    /// nella cartella locale e il progetto registrato col percorso nuovo.
    @discardableResult
    static func importAll(from selection: [URL]) throws -> Int {
        let (files, manifest) = collect(selection)
        return try copyIn(files: files, manifest: manifest)
    }

    /// Prova ad aprire un vault con una password diversa da quella dello
    /// scrigno: serve per i file che arrivano da un'altra installazione, o
    /// direttamente da KeePass.
    static func unlock(_ preview: Preview, with password: String) -> Preview? {
        guard let bytes = try? Data(contentsOf: preview.file),
              let db = try? Kdbx4.open(data: Array(bytes), password: password)
        else { return nil }
        var aperto = preview
        aperto.entries = db.allEntries.map(\.title)
        aperto.problem = nil
        aperto.foreignPassword = password
        return aperto
    }

    /// Importa solo quelli confermati nell'anteprima.
    @discardableResult
    static func importChosen(_ previews: [Preview]) throws -> Int {
        let (_, manifest) = collect(previews.map { $0.file.deletingLastPathComponent() })

        // quelli che arrivano con una password loro vanno ricifrati con la
        // nostra: dentro allo scrigno la chiave è una sola
        var daCopiare: [URL] = []
        var importati = 0
        for preview in previews {
            guard let foreign = preview.foreignPassword, let key = MasterKey.session else {
                daCopiare.append(preview.file)
                continue
            }
            let bytes = Array(try Data(contentsOf: preview.file))
            let db = try Kdbx4.open(data: bytes, password: foreign)
            let riscritto = try Kdbx4.save(database: db, password: key)
            let dest = VaultFileManager.shared.freeProjectURL(named: preview.name)
            try Data(riscritto).write(to: dest, options: .atomic)
            try VaultFileManager.shared.addProject(name: preview.name, url: dest,
                                                   icon: preview.icon, noteColor: preview.noteColor)
            importati += 1
        }
        return importati + (try copyIn(files: daCopiare, manifest: manifest))
    }

    /// Raccoglie i .kdbx dalla selezione (cartelle o file) e l'indice.
    private static func collect(_ selection: [URL]) -> ([URL], Manifest?) {
        let fm = FileManager.default
        var files: [URL] = []
        var manifest: Manifest?

        for url in selection {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let contents = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                files += contents.filter { $0.pathExtension.lowercased() == "kdbx" }
                // l'indice con nomi, icone e colori, se la cartella ce l'ha
                if manifest == nil,
                   let data = try? Data(contentsOf: url.appendingPathComponent(manifestName)) {
                    manifest = try? JSONDecoder().decode(Manifest.self, from: data)
                }
            } else if url.pathExtension.lowercased() == "kdbx" {
                files.append(url)
                // scelto il file da solo: l'indice sta comunque accanto
                if manifest == nil,
                   let data = try? Data(contentsOf: url.deletingLastPathComponent()
                                                      .appendingPathComponent(manifestName)) {
                    manifest = try? JSONDecoder().decode(Manifest.self, from: data)
                }
            }
        }
        return (files, manifest)
    }

    private static func copyIn(files: [URL], manifest: Manifest?) throws -> Int {
        let fm = FileManager.default
        var importati = 0
        for file in files {
            let dest = VaultFileManager.shared.freeProjectURL(named: file.deletingPathExtension().lastPathComponent)
            try fm.copyItem(at: file, to: dest)

            // nome, icona e colore vengono dall'indice, se c'è
            let original = manifest?.progetti.first { URL(fileURLWithPath: $0.path).lastPathComponent == file.lastPathComponent }
            try VaultFileManager.shared.addProject(
                name: original?.name ?? file.deletingPathExtension().lastPathComponent,
                url: dest,
                icon: original?.icon,
                noteColor: original?.noteColor
            )
            importati += 1
        }
        return importati
    }

    // MARK: - Pannelli

    static func chooseExportFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Esporta qui"
        panel.message = "Scegli dove mettere i cassetti"
        panel.begin { completion($0 == .OK ? panel.url : nil) }
    }

    /// Pannello d'importazione: accetta la cartella esportata **oppure** i
    /// singoli .kdbx. Prima prendeva solo cartelle, e i file esportati
    /// risultavano spenti e non selezionabili.
    static func chooseImport(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Importa"
        panel.message = "Scegli la cartella esportata, oppure i file .kdbx"
        panel.begin { completion($0 == .OK ? panel.urls : []) }
    }
}
