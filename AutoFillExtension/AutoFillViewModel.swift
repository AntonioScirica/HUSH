import Foundation
import VaultCore

@MainActor
final class AutoFillViewModel: ObservableObject {
    @Published var isUnlocked = false
    @Published var errorMessage: String?
    @Published var isBusy = false
    @Published var triedStoredPassword = false

    private var database: VaultDatabase?
    let serviceIdentifiers: [String]

    init(serviceIdentifiers: [String]) {
        self.serviceIdentifiers = serviceIdentifiers
    }

    /// Voci il cui URL combacia (anche solo parzialmente) col dominio richiesto
    /// da Safari/dall'app che ha invocato l'AutoFill.
    var matchingEntries: [VaultEntry] {
        guard let database else { return [] }
        let all = database.allEntries
        guard !serviceIdentifiers.isEmpty else { return all }
        let hosts = serviceIdentifiers.map { $0.lowercased() }
        let matched = all.filter { entry in
            guard let host = URL(string: entry.url)?.host?.lowercased(), !host.isEmpty else { return false }
            return hosts.contains { ident in ident.contains(host) || host.contains(ident) }
        }
        return matched.isEmpty ? all : matched
    }

    var hasStoredPassword: Bool { SharedKeychain.hasStoredPassword }
    var hasVault: Bool { VaultFileManager.shared.hasVault }

    func unlockWithStoredPasswordIfAvailable() async {
        guard !triedStoredPassword, SharedKeychain.hasStoredPassword else { return }
        triedStoredPassword = true
        isBusy = true
        defer { isBusy = false }
        guard let password = try? SharedKeychain.retrieve(prompt: "Sblocca Scrigno per compilare la password") else {
            return // l'utente potrà sempre sbloccare manualmente sotto
        }
        try? await openVault(password: password)
    }

    func unlock(withPassword password: String, rememberWithFaceID: Bool) async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await openVault(password: password)
            if rememberWithFaceID {
                try? SharedKeychain.store(password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openVault(password: String) async throws {
        let data = try VaultFileManager.shared.readVault()
        let db = try await Task.detached(priority: .userInitiated) {
            try Kdbx4.open(data: data, password: password)
        }.value
        self.database = db
        self.isUnlocked = true
    }
}
