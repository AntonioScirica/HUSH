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

    /// Rimette i vault di una cartella esportata dentro a questo computer.
    ///
    /// I percorsi dell'altro Mac non valgono qui: ogni file viene ricollocato
    /// nella cartella locale e il progetto registrato col percorso nuovo.
    @discardableResult
    static func importAll(from folder: URL) throws -> Int {
        let fm = FileManager.default
        let manifestURL = folder.appendingPathComponent(manifestName)
        let manifest = (try? Data(contentsOf: manifestURL))
            .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }

        // senza indice si importano comunque i .kdbx trovati: meglio i vault
        // senza icone che nessun vault
        let files = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "kdbx" } ?? []

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

    static func chooseImportFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Importa"
        panel.message = "Scegli la cartella esportata dall'altro computer"
        panel.begin { completion($0 == .OK ? panel.url : nil) }
    }
}
