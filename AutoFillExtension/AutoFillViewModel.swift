import Foundation
import VaultCore

@MainActor
final class AutoFillViewModel: ObservableObject {
    @Published var isUnlocked = false
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var triedStoredPassword = false

    /// Un vault per progetto: la master password è la stessa per tutti (vedi
    /// MasterKey nell'app principale), ma le voci restano separate per poterle
    /// etichettare col nome del progetto nell'elenco.
    private var databases: [String: VaultDatabase] = [:]
    private var projectNames: [String: String] = [:]
    let serviceIdentifiers: [String]

    init(serviceIdentifiers: [String]) {
        self.serviceIdentifiers = serviceIdentifiers
    }

    struct Match: Identifiable {
        let entry: VaultEntry
        let projectName: String
        var id: UUID { entry.id }
    }

    /// Voci il cui URL combacia (anche solo parzialmente) col dominio richiesto
    /// da Safari/dall'app che ha invocato l'AutoFill, cercate in TUTTI i
    /// progetti aperti. Se nessuna combacia si mostra comunque tutto: meglio
    /// scegliere a mano che restare a mani vuote.
    var matchingEntries: [Match] {
        guard !databases.isEmpty else { return [] }
        let hosts = serviceIdentifiers.map { $0.lowercased() }
        let all = databases.flatMap { path, db in
            db.allEntries.map { Match(entry: $0, projectName: projectNames[path] ?? "") }
        }
        guard !hosts.isEmpty else { return all.sorted { $0.entry.title < $1.entry.title } }

        let matched = all.filter { match in
            hosts.contains { host in HostMatch.matches(entryURL: match.entry.url, entryTitle: match.entry.title, host: host) }
        }
        return (matched.isEmpty ? all : matched).sorted { $0.entry.title < $1.entry.title }
    }

    var hasStoredPassword: Bool { SharedKeychain.hasStoredPassword }
    var hasVault: Bool { !VaultFileManager.shared.projects.isEmpty }

    func unlockWithStoredPasswordIfAvailable() async {
        guard !triedStoredPassword, SharedKeychain.hasStoredPassword else { return }
        triedStoredPassword = true
        isBusy = true
        defer { isBusy = false }
        // Il Portachiavi mostra Face ID e blocca finché non risponde: fuori
        // dal thread principale (questa classe è @MainActor), o l'estensione
        // resta con la UI congelata mentre aspetta il dito.
        let password = await Task.detached {
            try? SharedKeychain.retrieve(prompt: "Sblocca Hush per compilare la password")
        }.value
        guard let password else {
            return // l'utente potrà sempre sbloccare manualmente sotto
        }
        try? await openVaults(password: password)
    }

    func unlock(withPassword password: String, rememberWithFaceID: Bool) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await openVaults(password: password)
            if rememberWithFaceID {
                try? SharedKeychain.store(password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openVaults(password: String) async throws {
        let projects = VaultFileManager.shared.projects
        guard !projects.isEmpty else { throw VaultFileError.noFileChosen }

        let opened = try await Task.detached(priority: .userInitiated) { () -> [(VaultFileManager.Project, VaultDatabase)] in
            var result: [(VaultFileManager.Project, VaultDatabase)] = []
            for project in projects {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: project.path)) else { continue }
                let db = try Kdbx4.open(data: Array(data), password: password)
                result.append((project, db))
            }
            return result
        }.value

        self.databases = Dictionary(uniqueKeysWithValues: opened.map { ($0.0.path, $0.1) })
        self.projectNames = Dictionary(uniqueKeysWithValues: opened.map { ($0.0.path, $0.0.name) })
        self.isUnlocked = true
    }
}
