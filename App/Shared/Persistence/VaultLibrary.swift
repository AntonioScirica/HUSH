import Foundation
import Combine
import VaultCore

/// Tiene aperti i vault dei progetti, uno per file `.kdbx`.
///
/// Tre scelte che contano:
///
/// - **Caricamento pigro.** Un vault si apre solo quando serve davvero.
///   Aprirli tutti all'avvio vorrebbe dire pagare Argon2id per ognuno, e
///   Argon2id è lento di proposito: mezzo secondo a progetto.
/// - **Salvataggio differito.** Le modifiche si accumulano e finiscono su
///   disco dopo un attimo di quiete. Salvare a ogni tasto premuto
///   significherebbe rifare la derivazione della chiave ogni volta.
/// - **Una chiave sola.** Tutti i file sono cifrati con la master password
///   della sessione: è quella che si digita alla porta del caveau.
@MainActor
final class VaultLibrary: ObservableObject {
    static let shared = VaultLibrary()
    private init() {}

    /// Ultimo errore incontrato aprendo o scrivendo un vault.
    @Published var failure: String?

    /// Vault aperti, per percorso del file.
    private var open: [String: VaultDatabase] = [:]
    /// Progetti con modifiche non ancora scritte.
    private var dirty: Set<String> = []
    private var saveTasks: [String: Task<Void, Never>] = [:]

    /// Quanto si aspetta prima di scrivere: abbastanza da coprire una
    /// raffica di modifiche, abbastanza poco da non perdere niente.
    private let saveDelay: Duration = .seconds(2)

    // MARK: - Lettura

    /// Voci di un progetto. La prima volta apre il file; poi risponde a memoria.
    func entries(of project: VaultFileManager.Project) -> [VaultEntry] {
        database(of: project)?.allEntries ?? []
    }

    func isLoaded(_ project: VaultFileManager.Project) -> Bool {
        open[project.path] != nil
    }

    @discardableResult
    func database(of project: VaultFileManager.Project) -> VaultDatabase? {
        if let db = open[project.path] { return db }
        guard let key = MasterKey.session else { return nil }
        do {
            let bytes = Array(try Data(contentsOf: URL(fileURLWithPath: project.path)))
            let db = try Kdbx4.open(data: bytes, password: key)
            open[project.path] = db
            return db
        } catch {
            failure = "Non riesco ad aprire «\(project.name)»: \(error.localizedDescription)"
            return nil
        }
    }

    /// Apre in anticipo i vault non ancora caricati, uno alla volta e fuori
    /// dal thread principale: Argon2id è lento di proposito e sul main thread
    /// inchioderebbe la finestra per mezzo secondo a progetto.
    func preload(_ projects: [VaultFileManager.Project]) async {
        guard let key = MasterKey.session else { return }
        for project in projects where open[project.path] == nil {
            let path = project.path
            let loaded = await Task.detached(priority: .userInitiated) { () -> VaultDatabase? in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
                return try? Kdbx4.open(data: Array(data), password: key)
            }.value
            guard let loaded else { continue }
            open[path] = loaded
            objectWillChange.send()
        }
    }

    /// Chiede il caricamento di un vault SENZA aspettarlo.
    ///
    /// Argon2id costa mezzo secondo: farlo mentre SwiftUI sta disegnando
    /// significa inchiodare la finestra. Qui si avvia e basta; quando il vault
    /// è pronto la vista si ridisegna da sé.
    func requestLoad(_ project: VaultFileManager.Project) {
        guard open[project.path] == nil, !loading.contains(project.path) else { return }
        loading.insert(project.path)
        Task { [weak self] in
            await self?.preload([project])
            self?.loading.remove(project.path)
        }
    }

    private var loading: Set<String> = []

    // MARK: - Scrittura

    func add(_ entry: VaultEntry, to project: VaultFileManager.Project) {
        guard let db = database(of: project) else { return }
        db.addEntry(entry)
        touch(project)
    }

    func update(_ entry: VaultEntry, in project: VaultFileManager.Project) {
        guard let db = database(of: project) else { return }
        db.updateEntry(entry)
        touch(project)
    }

    func delete(id: UUID, from project: VaultFileManager.Project) {
        guard let db = database(of: project) else { return }
        db.deleteEntry(id: id)
        touch(project)
    }

    /// Segna il progetto come da salvare e fa ripartire l'attesa. Ogni nuova
    /// modifica annulla il salvataggio in coda: si scrive una volta sola, a
    /// mano ferma.
    private func touch(_ project: VaultFileManager.Project) {
        dirty.insert(project.path)
        objectWillChange.send()

        saveTasks[project.path]?.cancel()
        saveTasks[project.path] = Task { [weak self] in
            try? await Task.sleep(for: self?.saveDelay ?? .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.flush(project)
        }
    }

    /// Scrive subito un progetto, se ha modifiche in sospeso.
    ///
    /// Anche il salvataggio passa da Argon2id: sul thread principale sarebbe
    /// mezzo secondo di finestra bloccata a ogni scrittura, cioè in pratica
    /// dopo ogni modifica. La cifratura va fuori, la scrittura su disco pure.
    func flush(_ project: VaultFileManager.Project) {
        guard dirty.contains(project.path),
              let db = open[project.path],
              let key = MasterKey.session else { return }
        dirty.remove(project.path)
        let path = project.path
        let nome = project.name

        Task { [weak self] in
            let esito: String? = await Task.detached(priority: .utility) { () -> String? in
                do {
                    // Scrittura in due tempi: prima un file di lavoro accanto,
                    // poi lo scambio. Se la corrente va via a metà, il vault
                    // buono è ancora lì — sovrascrivendo in posto si resterebbe
                    // con un file monco.
                    let bytes = try Kdbx4.save(database: db, password: key)
                    let url = URL(fileURLWithPath: path)
                    let temp = url.appendingPathExtension("tmp")
                    try Data(bytes).write(to: temp, options: .atomic)
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let esito {
                self?.dirty.insert(path)   // ritenta al prossimo giro
                self?.failure = "Non riesco a salvare «\(nome)»: \(esito)"
            }
        }
    }

    /// Salvataggio bloccante, per quando si chiude lo scrigno: lì la chiave
    /// sta per sparire dalla memoria e non si può rimandare.
    private func flushNow(_ project: VaultFileManager.Project) {
        guard dirty.contains(project.path),
              let db = open[project.path],
              let key = MasterKey.session else { return }
        do {
            let bytes = try Kdbx4.save(database: db, password: key)
            let url = URL(fileURLWithPath: project.path)
            let temp = url.appendingPathExtension("tmp")
            try Data(bytes).write(to: temp, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
            dirty.remove(project.path)
        } catch {
            failure = "Non riesco a salvare «\(project.name)»: \(error.localizedDescription)"
        }
    }

    /// Scrive tutto quel che è in sospeso: da chiamare prima di richiudere lo
    /// scrigno o di uscire dall'app, o le ultime modifiche resterebbero a mezz'aria.
    func flushAll(_ projects: [VaultFileManager.Project]) {
        saveTasks.values.forEach { $0.cancel() }
        saveTasks = [:]
        for project in projects where dirty.contains(project.path) {
            flushNow(project)
        }
    }

    /// A scrigno chiuso in memoria non resta niente di decifrato.
    func closeAll(_ projects: [VaultFileManager.Project]) {
        flushAll(projects)
        open = [:]
        dirty = []
    }
}
