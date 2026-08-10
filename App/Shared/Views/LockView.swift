import SwiftUI
import VaultCore

struct LockView: View {
    @EnvironmentObject var vm: VaultViewModel

    @State private var openPassword = ""
    @State private var pendingOpenData: [UInt8]?
    @State private var pendingOpenURL: URL?
    @State private var showOpenPasswordSheet = false

    @State private var showFileImporter = false
    @State private var localError: String?

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 36)
                        chooser
                            .frame(maxWidth: 460)
                            .padding(.horizontal, 28)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: max(geo.size.height * 0.55, 260))
                }

                inkPanel
            }
        }
        .paperBackground()
        .preferredColorScheme(.light)
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.kdbx, .data]) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showOpenPasswordSheet) {
            openPasswordSheet
        }
        .alert("Errore", isPresented: .constant(localError != nil), actions: {
            Button("OK") { localError = nil }
        }, message: { Text(localError ?? "") })
    }

    // MARK: - Pannello nero in basso (stile slide "SERVICES")

    private var inkPanel: some View {
        VStack(spacing: 10) {
            Text("Il tuo vault di password")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.paper.opacity(0.6))

            HStack(alignment: .top, spacing: 0) {
                Text("HUSH")
                    .font(Theme.display(56))
                    .kerning(-1)
                    .foregroundStyle(Theme.paper)
                Text("Offline")
                    .font(Theme.mono(11, .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.yellow, in: Capsule())
                    .rotationEffect(.degrees(-8))
                    .offset(x: -6, y: 2)
            }

            Text("TUTTO QUI DENTRO · NESSUN SERVER")
                .font(Theme.mono(10))
                .tracking(2)
                .foregroundStyle(Theme.paper.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(Theme.ink)
    }

    // MARK: - Chooser: una sola linguetta, apri vault esistente
    // (creazione nuovo vault disattivata temporaneamente — TODO riattivare)

    private var chooser: some View {
        FolderTabButton(number: 1, title: "Apri vault esistente", alignment: .leading, filled: true) {
            showFileImporter = true
        }
    }

    // MARK: - Apertura

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try? VaultFileManager.shared.rememberVaultLocation(url)
                pendingOpenData = Array(data)
                pendingOpenURL = url
                showOpenPasswordSheet = true
            } catch {
                localError = "Impossibile leggere il file: \(error.localizedDescription)"
            }
        case .failure(let error):
            localError = "Selezione file non riuscita: \(error.localizedDescription)"
        }
    }

    private var openPasswordSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            IndexLabel(number: 3, text: "Master password")
            SecureField("Master password", text: $openPassword)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit { attemptOpen() }
            if vm.isBusy {
                ProgressView("Decifro il vault…")
                    .font(Theme.mono(11))
                    .tint(Theme.ink)
            }
            HStack(spacing: 10) {
                Button("Annulla") {
                    showOpenPasswordSheet = false
                    openPassword = ""
                }
                .buttonStyle(OutlineButtonStyle())
                .frame(width: 110)
                Button("Apri") { attemptOpen() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .disabled(openPassword.isEmpty || vm.isBusy)
                    .opacity(openPassword.isEmpty || vm.isBusy ? 0.4 : 1)
            }
        }
        .padding(26)
        .frame(minWidth: 360)
        .background(Theme.paper)
        .preferredColorScheme(.light)
    }

    private func attemptOpen() {
        guard let data = pendingOpenData else { return }
        Task {
            await vm.open(fileData: data, password: openPassword)
            openPassword = ""
            if vm.isUnlocked {
                showOpenPasswordSheet = false
            } else if let err = vm.errorMessage {
                localError = err
                vm.errorMessage = nil
            }
        }
    }
}

/// Linguetta di cartellina cliccabile, con numero e titolo, appoggiata su una
/// riga che attraversa tutta la larghezza (come i divider delle reference).
struct FolderTabButton: View {
    let number: Int
    let title: String
    var alignment: HorizontalAlignment = .leading
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack {
                    if alignment == .trailing { Spacer(minLength: 0) }
                    IndexLabel(number: number, text: title, inverted: filled)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 13)
                        .background(
                            TabShape().fill(filled ? Theme.ink : Theme.paperRaised)
                        )
                        .overlay(TabShape().stroke(Theme.line, lineWidth: 1.2))
                    if alignment == .leading { Spacer(minLength: 0) }
                }
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1.2)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
