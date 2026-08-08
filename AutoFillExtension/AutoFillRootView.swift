import SwiftUI
import VaultCore

struct AutoFillRootView: View {
    @StateObject var vm: AutoFillViewModel
    var preselectId: String?
    let onSelect: (String, String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var rememberFaceID = true
    @State private var attemptedAutoUnlock = false

    var body: some View {
        NavigationStack {
            Group {
                if !vm.hasVault {
                    ContentUnavailableView(
                        "Nessun vault configurato",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Apri prima l'app Scrigno e crea o importa il tuo vault.")
                    )
                } else if vm.isUnlocked {
                    entryList
                } else {
                    unlockForm
                }
            }
            .navigationTitle("Scrigno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { onCancel() }
                }
            }
        }
        .task {
            guard !attemptedAutoUnlock else { return }
            attemptedAutoUnlock = true
            await vm.unlockWithStoredPasswordIfAvailable()
        }
    }

    private var entryList: some View {
        List(vm.matchingEntries) { entry in
            Button {
                onSelect(entry.username, entry.password)
            } label: {
                VStack(alignment: .leading) {
                    Text(entry.title).font(.body.weight(.medium))
                    if !entry.username.isEmpty {
                        Text(entry.username).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if vm.matchingEntries.isEmpty {
                ContentUnavailableView("Nessuna voce corrispondente", systemImage: "key")
            }
        }
    }

    private var unlockForm: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🔐").font(.system(size: 40))
            Text("Sblocca Scrigno").font(.headline)
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 32)
                .onSubmit { attemptUnlock() }
            Toggle("Ricorda con Face ID", isOn: $rememberFaceID)
                .padding(.horizontal, 32)
            if vm.isBusy {
                ProgressView()
            } else {
                Button("Sblocca") { attemptUnlock() }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
            if let error = vm.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    private func attemptUnlock() {
        Task {
            await vm.unlock(withPassword: password, rememberWithFaceID: rememberFaceID)
            password = ""
        }
    }
}
