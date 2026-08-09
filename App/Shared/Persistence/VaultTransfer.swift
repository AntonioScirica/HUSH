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

    /// Crea una cartella sua dentro a quella scelta e ci mette dentro tutto.
    ///
    /// Una cartella propria e non i file sparsi: così l'esportazione si
    /// riconosce a colpo d'occhio, si sposta in un pezzo solo, e reimportarla
    /// vuol dire indicare una cartella invece di ripescare venti file.
    @discardableResult
    static func export(to parent: URL) throws -> (count: Int, folder: URL) {
        try exportSync(to: parent,
                       projects: VaultFileManager.shared.projects,
                       vaultDir: VaultFileManager.shared.projectsDirectory)
    }

    private static func exportSync(to parent: URL,
                                   projects: [VaultFileManager.Project],
                                   vaultDir: URL) throws -> (count: Int, folder: URL) {
        let fm = FileManager.default

        // Esportare dentro alla cartella dei vault vorrebbe dire copiare ogni
        // file su sé stesso: sotto c'è una rimozione del file di destinazione,
        // che qui cancellerebbe l'originale. Meglio fermarsi prima.
        guard parent.standardizedFileURL != vaultDir.standardizedFileURL else {
            throw Failure.exportingOntoItself
        }

        let giorno = DateFormatter()
        giorno.dateFormat = "yyyy-MM-dd"
        let base = "Scrigno cassetti \(giorno.string(from: Date()))"
        var folder = parent.appendingPathComponent(base)
        var n = 2
        while fm.fileExists(atPath: folder.path) {
            folder = parent.appendingPathComponent("\(base) (\(n))")
            n += 1
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

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
        return (projects.count, folder)
    }

    /// Esportazione fuori dal thread principale: copiare venti file mentre la
    /// finestra aspetta si sente, soprattutto su disco esterno o chiavetta.
    @MainActor
    static func exportAsync(to parent: URL) async throws -> (count: Int, folder: URL) {
        let projects = VaultFileManager.shared.projects
        let vaultDir = VaultFileManager.shared.projectsDirectory
        return try await Task.detached(priority: .userInitiated) {
            try exportSync(to: parent, projects: projects, vaultDir: vaultDir)
        }.value
    }

    // MARK: - Aspetto dei cassetti importati

    /// Icone per i cassetti che arrivano da fuori.
    ///
    /// Si pescano in ordine e senza ripetersi finché ce n'è: importando
    /// diciotto vault tutti uguali non si distinguerebbe più niente, e la
    /// parete serve proprio a riconoscere i progetti a colpo d'occhio. I
    /// colori invece possono ripetersi, sono pochi di proposito.
    private static let iconePerImport = [
        "folder", "briefcase", "house", "globe", "cart", "creditcard",
        "person.2", "building.2", "gamecontroller", "airplane", "car",
        "heart", "graduationcap", "music.note", "camera", "leaf",
        "bolt", "cross.case", "hammer", "chart.bar", "envelope", "phone",
        "book", "gift", "ticket", "shippingbox", "server.rack", "wifi",
        "key", "lock.shield", "star", "flag"
    ]

    static func aspetto(perIndice i: Int) -> (icon: String, color: String) {
        let icona = iconePerImport[i % iconePerImport.count]
        let colori = ["#FADA5C", "#F4A9A8", "#A8D8B9", "#9EC5E8", "#D9B8E8", "#F0C9A0"]
        return (icona, colori[i % colori.count])
    }

    // MARK: - Anteprima

    /// Da dove arriva un cassetto da importare. Le tre provenienze si
    /// comportano diversamente in scrittura, ma nell'anteprima si guardano
    /// tutte allo stesso modo: nome, quante voci, quali.
    enum Origin {
        /// un .kdbx già cifrato: si copia, o si ricifra se ha una sua password
        case kdbx
        /// righe lette da un .csv
        case csv([ImportedEntry])
        /// un vault di 1Password
        case onePassword(OnePasswordImport.Vault)
    }

    /// Cosa c'è dentro a un file da importare, prima di importarlo.
    struct Preview: Identifiable {
        let id = UUID()
        var origin: Origin = .kdbx
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
    /// Versione fuori dal thread principale: aprire venti vault con Argon2id
    /// mentre la finestra aspetta vuol dire dieci secondi di app congelata.
    static func inspect(_ selection: [URL], key: String?) async -> [Preview] {
        await Task.detached(priority: .userInitiated) {
            inspectSync(selection, key: key)
        }.value
    }

    /// Guarda dentro a qualunque cosa sia stata scelta: cartelle, .kdbx,
    /// .csv, archivi .1pux. Un solo comando d'importazione, e a capire cosa
    /// sia ci pensa lui.
    static func inspectAny(_ selection: [URL], key: String?) async -> [Preview] {
        await Task.detached(priority: .userInitiated) {
            var previews: [Preview] = []
            var perKdbx: [URL] = []
            // contatore unico su tutta l'importazione: due vault non devono
            // ritrovarsi con la stessa icona solo perché arrivano da file diversi
            var prossimo = 0
            func aspettoSuccessivo() -> (icon: String, color: String) {
                defer { prossimo += 1 }
                return aspetto(perIndice: prossimo)
            }

            for url in selection {
                switch url.pathExtension.lowercased() {
                case "csv", "txt":
                    if let entries = try? CSVImport.parse(contentsOf: url) {
                        let look = aspettoSuccessivo()
                        previews.append(Preview(
                            origin: .csv(entries),
                            file: url,
                            name: url.deletingPathExtension().lastPathComponent,
                            icon: look.icon,
                            noteColor: look.color,
                            entries: entries.map(\.title)
                        ))
                    } else {
                        previews.append(Preview(file: url,
                                                name: url.lastPathComponent,
                                                problem: "csv illeggibile"))
                    }

                case "1pux":
                    if let vaults = try? OnePasswordImport.read(url) {
                        for v in vaults {
                            let look = aspettoSuccessivo()
                            previews.append(Preview(
                                origin: .onePassword(v),
                                file: url,
                                name: v.name,
                                icon: look.icon,
                                noteColor: look.color,
                                entries: v.entries.map(\.title) + v.details.map(\.title)
                            ))
                        }
                    } else {
                        previews.append(Preview(file: url,
                                                name: url.lastPathComponent,
                                                problem: "archivio illeggibile"))
                    }

                default:
                    perKdbx.append(url)
                }
            }

            previews += inspectSync(perKdbx, key: key)
            return previews
        }.value
    }

    static func inspectSync(_ selection: [URL], key: String?) -> [Preview] {
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
            guard let key else {
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

    /// Come `importChosen`, ma la parte pesante (ricifrare ogni vault con la
    /// master password) sta fuori dal thread principale.
    @MainActor
    static func importChosenAsync(_ previews: [Preview]) async throws -> Int {
        let key = MasterKey.session
        let cartellaVault = VaultFileManager.shared.projectsDirectory

        // fuori: apertura e ricifratura, cioè i due Argon2id per cassetto
        struct Pronto { let name: String; let icon: String?; let noteColor: String?; let bytes: [UInt8]?; let source: URL }
        let pronti: [Pronto] = await Task.detached(priority: .userInitiated) {
            previews.map { p in
                func vuoto() -> Pronto {
                    Pronto(name: p.name, icon: p.icon, noteColor: p.noteColor, bytes: nil, source: p.file)
                }
                switch p.origin {
                case .csv(let entries):
                    guard let key else { return vuoto() }
                    let db = VaultDatabase.createNew(name: p.name)
                    for e in entries {
                        db.addEntry(VaultEntry(
                            title: e.title, username: e.username, password: e.password,
                            url: e.url, notes: e.notes,
                            customFields: [VaultCustomField(key: "scrigno.kind", value: "login")]
                        ))
                    }
                    return Pronto(name: p.name, icon: p.icon, noteColor: p.noteColor,
                                  bytes: try? Kdbx4.save(database: db, password: key), source: p.file)

                case .onePassword(let vault):
                    guard let key else { return vuoto() }
                    let db = VaultDatabase.createNew(name: vault.name)
                    for e in vault.entries {
                        db.addEntry(VaultEntry(
                            title: e.title, username: e.username, password: e.password,
                            url: e.url, notes: e.notes,
                            customFields: [VaultCustomField(key: "scrigno.kind", value: "login")]
                        ))
                    }
                    for d in vault.details {
                        db.addEntry(VaultEntry(
                            title: d.title,
                            customFields: [VaultCustomField(key: "scrigno.kind",
                                                            value: d.kind == "extra" ? "secureNote" : d.kind)]
                                + d.fields.map { VaultCustomField(key: $0.label, value: $0.value) }
                        ))
                    }
                    return Pronto(name: p.name, icon: p.icon, noteColor: p.noteColor,
                                  bytes: try? Kdbx4.save(database: db, password: key), source: p.file)

                case .kdbx:
                    guard let foreign = p.foreignPassword, let key,
                          let data = try? Data(contentsOf: p.file),
                          let db = try? Kdbx4.open(data: Array(data), password: foreign),
                          let riscritto = try? Kdbx4.save(database: db, password: key)
                    else { return vuoto() }
                    return Pronto(name: p.name, icon: p.icon, noteColor: p.noteColor,
                                  bytes: riscritto, source: p.file)
                }
            }
        }.value
        _ = cartellaVault

        // dentro: solo scritture e registrazione, che costano niente
        var importati = 0
        for p in pronti {
            let dest = VaultFileManager.shared.freeProjectURL(named: p.name)
            if let bytes = p.bytes {
                try Data(bytes).write(to: dest, options: .atomic)
            } else {
                try FileManager.default.copyItem(at: p.source, to: dest)
            }
            try VaultFileManager.shared.addProject(name: p.name, url: dest,
                                                   icon: p.icon, noteColor: p.noteColor)
            importati += 1
        }
        return importati
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

    // MARK: - Da 1Password

    /// Crea un cassetto per ogni vault di 1Password, con dentro le sue voci.
    /// Il lavoro pesante (un Argon2id per cassetto) sta fuori dal thread
    /// principale, così la finestra non si pianta con archivi grossi.
    @MainActor
    static func importOnePassword(_ archive: URL) async throws -> (cassetti: Int, voci: Int) {
        guard let key = MasterKey.session else { throw OnePasswordImport.Failure.noVaults }
        let vaults = try await Task.detached(priority: .userInitiated) {
            try OnePasswordImport.read(archive)
        }.value

        struct Pronto { let name: String; let bytes: [UInt8]; let voci: Int }
        let pronti: [Pronto] = await Task.detached(priority: .userInitiated) {
            vaults.compactMap { vault in
                let db = VaultDatabase.createNew(name: vault.name)
                for e in vault.entries {
                    db.addEntry(VaultEntry(
                        title: e.title, username: e.username, password: e.password,
                        url: e.url, notes: e.notes,
                        customFields: [VaultCustomField(key: "scrigno.kind", value: "login")]
                    ))
                }
                for d in vault.details {
                    db.addEntry(VaultEntry(
                        title: d.title,
                        customFields: [VaultCustomField(key: "scrigno.kind",
                                                        value: d.kind == "extra" ? "secureNote" : d.kind)]
                            + d.fields.map { VaultCustomField(key: $0.label, value: $0.value) }
                    ))
                }
                guard let bytes = try? Kdbx4.save(database: db, password: key) else { return nil }
                return Pronto(name: vault.name, bytes: bytes, voci: db.allEntries.count)
            }
        }.value

        for p in pronti {
            let dest = VaultFileManager.shared.freeProjectURL(named: p.name)
            try Data(p.bytes).write(to: dest, options: .atomic)
            try VaultFileManager.shared.addProject(name: p.name, url: dest,
                                                   icon: "lock.shield",
                                                   noteColor: "#A8D8B9")
        }
        return (pronti.count, pronti.reduce(0) { $0 + $1.voci })
    }

    static func chooseOnePasswordArchive(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.prompt = "Importa"
        panel.message = "Scegli l'archivio .1pux esportato da 1Password"
        panel.begin { completion($0 == .OK ? panel.url : nil) }
    }

    // MARK: - Pannelli

    static func chooseExportFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Esporta qui"
        panel.message = "Scegli dove creare la cartella coi cassetti"
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
        panel.message = "Cassetti esportati, file .kdbx, .csv o archivi .1pux di 1Password"
        panel.begin { completion($0 == .OK ? panel.urls : []) }
    }
}
