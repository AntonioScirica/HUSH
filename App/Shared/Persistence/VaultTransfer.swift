import Foundation
import AppKit

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

    /// Copia tutti i vault e l'indice nella cartella scelta.
    @discardableResult
    static func export(to folder: URL) throws -> Int {
        let projects = VaultFileManager.shared.projects
        let fm = FileManager.default

        for project in projects {
            let source = URL(fileURLWithPath: project.path)
            guard fm.fileExists(atPath: source.path) else { continue }
            let dest = folder.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
        }

        let manifest = Manifest(progetti: projects, esportato: Date().timeIntervalSince1970)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: folder.appendingPathComponent(manifestName), options: .atomic)
        return projects.count
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
