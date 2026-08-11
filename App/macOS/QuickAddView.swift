import SwiftUI
import VaultCore
import LocalAuthentication

/// Il popup della scorciatoia globale (⌃⌥H): sblocco, poi progetto, poi la
/// voce da salvare. Tre passi, uno schermo alla volta — niente altro sul
/// tragitto fra "premo il tasto" e "la password è salvata".
struct QuickAddView: View {
    let onDone: () -> Void

    private enum Passo { case sblocco, progetto, modulo }
    @State private var passo: Passo = .sblocco
    @State private var progettoScelto: VaultFileManager.Project?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.line)

            switch passo {
            case .sblocco:
                SbloccoRapido {
                    passo = VaultFileManager.shared.projects.count == 1 ? .modulo : .progetto
                    if VaultFileManager.shared.projects.count == 1 {
                        progettoScelto = VaultFileManager.shared.projects.first
                    }
                }
            case .progetto:
                SceltaProgetto { progetto in
                    progettoScelto = progetto
                    passo = .modulo
                }
            case .modulo:
                if let progettoScelto {
                    ModuloVoce(progetto: progettoScelto, onSalvato: onDone)
                }
            }
        }
        .frame(width: 420)
        .background(Theme.paper)
        .onExitCommand { onDone() } // Esc chiude
    }

    private var header: some View {
        HStack {
            Text("HUSH").font(Theme.display(15)).kerning(-0.5)
            Spacer()
            Text(titolo)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.inkSoft)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var titolo: String {
        switch passo {
        case .sblocco: "sblocca"
        case .progetto: "scegli il progetto"
        case .modulo: "nuova voce"
        }
    }
}

// MARK: - Passo 1: sblocco

private struct SbloccoRapido: View {
    let onSbloccato: () -> Void

    @State private var password = ""
    @State private var errore: String?
    @State private var tentatoTouchID = false

    var body: some View {
        VStack(spacing: 14) {
            if MasterKey.isUnlocked {
                // la sessione principale è già aperta: niente da chiedere
                Color.clear.frame(height: 1)
                    .onAppear { onSbloccato() }
            } else {
                SecureField("Master password", text: $password)
                    .textFieldStyle(PaperFieldStyle())
                    .onSubmit(prova)

                if let errore {
                    Text(errore).font(Theme.mono(10)).foregroundStyle(Theme.danger)
                }

                Button("Sblocca") { prova() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .disabled(password.isEmpty)
                    .opacity(password.isEmpty ? 0.4 : 1)

                if MasterKey.biometryUsable {
                    Button {
                        proviamoTouchID()
                    } label: {
                        Label("Usa Touch ID", systemImage: "touchid")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }
            }
        }
        .padding(16)
        .task {
            guard !tentatoTouchID, MasterKey.biometryUsable else { return }
            tentatoTouchID = true
            proviamoTouchID()
        }
    }

    private func prova() {
        if MasterKey.unlock(password: password) {
            onSbloccato()
        } else {
            errore = "Password sbagliata."
            password = ""
        }
    }

    private func proviamoTouchID() {
        MasterKey.unlockWithBiometry { ok in
            if ok { onSbloccato() }
        }
    }
}

// MARK: - Passo 2: scelta progetto

private struct SceltaProgetto: View {
    let onScelto: (VaultFileManager.Project) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(VaultFileManager.shared.projects) { progetto in
                    Button { onScelto(progetto) } label: {
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(progetto.noteColor.map { Color(hex: $0) } ?? Theme.yellow)
                                .frame(width: 10, height: 10)
                            Text(progetto.name).font(Theme.mono(13))
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 280)
    }
}

// MARK: - Passo 3: modulo voce

private struct ModuloVoce: View {
    let progetto: VaultFileManager.Project
    let onSalvato: () -> Void

    @State private var titolo = ""
    @State private var utente = ""
    @State private var password = ""
    @State private var url = ""
    @State private var rivelaPassword = false

    var body: some View {
        VStack(spacing: 10) {
            Text(progetto.name).font(Theme.mono(10)).foregroundStyle(Theme.inkSoft)

            TextField("Titolo", text: $titolo).textFieldStyle(PaperFieldStyle())
            TextField("Utente / email", text: $utente).textFieldStyle(PaperFieldStyle())

            HStack(spacing: 8) {
                Group {
                    if rivelaPassword {
                        TextField("Password", text: $password)
                    } else {
                        SecureField("Password", text: $password)
                    }
                }
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                .padding(.horizontal, 10)
                .frame(height: Theme.fieldHeight)
                .background(Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

                Button { rivelaPassword.toggle() } label: {
                    Image(systemName: rivelaPassword ? "eye.slash" : "eye")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkSoft)

                Button { password = PasswordGenerator.generate(.init(length: 20)) } label: {
                    Image(systemName: "die.face.5")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkSoft)
                .help("genera una password casuale")
            }

            TextField("URL (facoltativo)", text: $url).textFieldStyle(PaperFieldStyle())

            Button("Salva") { salva() }
                .buttonStyle(InkButtonStyle(prominent: true))
                .disabled(titolo.isEmpty)
                .opacity(titolo.isEmpty ? 0.4 : 1)
        }
        .padding(16)
    }

    private func salva() {
        let voce = VaultEntry(title: titolo, username: utente, password: password, url: url)
        VaultLibrary.shared.add(voce, to: progetto)
        onSalvato()
    }
}
