import Foundation
import VaultCore

/// Fonde i cassetti che arrivano dall'altro dispositivo con quelli locali,
/// voce per voce: stesso id → vince la modifica più recente, id nuovo →
/// si aggiunge. Nessuno dei due lati "vince" in blocco: le aggiunte di qua
/// e le modifiche di là si intrecciano.
///
/// ponytail: le eliminazioni non si propagano — una voce cancellata su un
/// dispositivo ricompare al sync se l'altro la ha ancora (per distinguere
/// "cancellata di qua" da "aggiunta di là" servirebbero le lapidi, che il
/// formato KDBX di suo non porta in giro). Da aggiungere se diventa un
/// problema reale.
enum VaultMerge {

    /// Fonde `incoming` dentro `local`. Ritorna quante voci sono state
    /// aggiunte o aggiornate in `local`.
    static func merge(into local: VaultDatabase, from incoming: VaultDatabase) -> Int {
        let mie = Dictionary(uniqueKeysWithValues: local.allEntries.map { ($0.id, $0) })
        var cambi = 0
        for voce in incoming.allEntries {
            if let mia = mie[voce.id] {
                if voce.modified > mia.modified {
                    local.updateEntry(voce)
                    cambi += 1
                }
            } else {
                local.addEntry(voce)
                cambi += 1
            }
        }
        return cambi
    }

    /// Fonde i .kdbx dentro `cartella` (l'atterraggio di LocalSync) nei
    /// progetti locali: stesso nome → merge nel file esistente, nome nuovo →
    /// importazione normale. `key` è la master password, la stessa sui due
    /// dispositivi. Ritorna (progetti nuovi, progetti fusi, voci cambiate).
    @discardableResult
    static func mergeAll(from cartella: URL, key: String) throws -> (nuovi: Int, fusi: Int, voci: Int) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: cartella, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "kdbx" } ?? []

        let progetti = VaultFileManager.shared.projects
        var daImportare: [URL] = []
        var fusi = 0, voci = 0

        for file in files {
            let nome = file.deletingPathExtension().lastPathComponent
            // il file esportato si chiama come il progetto: è il nome il
            // ponte fra i due dispositivi, gli UUID di gruppo non viaggiano
            guard let esistente = progetti.first(where: { $0.name == nome }) else {
                daImportare.append(file)
                continue
            }
            let localBytes = try Data(contentsOf: URL(fileURLWithPath: esistente.path))
            let incomingBytes = try Data(contentsOf: file)
            let localDb = try Kdbx4.open(data: Array(localBytes), password: key)
            let incomingDb = try Kdbx4.open(data: Array(incomingBytes), password: key)
            let cambi = merge(into: localDb, from: incomingDb)
            if cambi > 0 {
                let salvato = try Kdbx4.save(database: localDb, password: key)
                try Data(salvato).write(to: URL(fileURLWithPath: esistente.path), options: .atomic)
                // la copia in memoria della libreria è rimasta indietro:
                // va buttata (sul main actor, dove la libreria vive)
                Task { @MainActor in VaultLibrary.shared.invalida(esistente) }
            }
            fusi += 1
            voci += cambi
        }

        var nuovi = 0
        if !daImportare.isEmpty {
            // solo i file col nome nuovo: passare la cartella intera
            // re-importerebbe anche i doppioni appena fusi. L'indice con
            // nomi/icone/colori sta accanto ai file: `collect` lo trova da sé.
            nuovi = try VaultTransfer.importAll(from: daImportare)
        }
        return (nuovi, fusi, voci)
    }
}
