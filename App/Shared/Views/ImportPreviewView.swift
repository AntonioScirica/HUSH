import SwiftUI

/// Cosa sta per entrare nelHush, prima che entri.
///
/// Importare alla cieca è rischioso in un modo poco ovvio: un vault che arriva
/// da un altro computer può essere cifrato con un'altra master password, e da
/// qui dentro diventerebbe un cassetto che non si apre. Qui si vede subito, e
/// quei cassetti non si possono nemmeno spuntare.
struct ImportPreviewView: View {
    @State var previews: [VaultTransfer.Preview]
    let onConfirm: ([VaultTransfer.Preview]) -> Void
    let onCancel: () -> Void

    @State private var chosen: Set<UUID> = []
    @State private var expanded: Set<UUID> = []
    /// Riga per cui si sta chiedendo la sua password.
    @State private var unlocking: VaultTransfer.Preview?
    @State private var foreignPassword = ""
    @State private var unlockError: String?
    @State private var provando = false

    private var selectable: [VaultTransfer.Preview] { previews.filter(\.isReadable) }
    private var selected: [VaultTransfer.Preview] { previews.filter { chosen.contains($0.id) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                IndexLabel(text: "Cosa stai importando")
                Rectangle().fill(Theme.line).frame(height: 1.2)
            }
            .padding(.bottom, 16)

            if previews.isEmpty {
                Text("In quella cartella non ci sono cassetti.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(previews) { preview in
                            riga(preview)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 10) {
                Button("Annulla") { onCancel() }
                    .buttonStyle(OutlineButtonStyle())
                Button(selected.isEmpty ? "Importa" : "Importa \(selected.count)") {
                    onConfirm(selected)
                }
                .buttonStyle(InkButtonStyle(prominent: true))
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.4 : 1)
            }
            .padding(.top, 16)
        }
        .padding(30)
        .frame(width: 480, height: 520)
        .background(Theme.paper)
        .preferredColorScheme(.light)
        // di norma si vuole tutto: le spunte partono già messe, tranne su
        // quelli che non si aprono
        .onAppear { chosen = Set(selectable.map(\.id)) }
        .sheet(item: $unlocking) { p in
            VStack(alignment: .leading, spacing: 16) {
                IndexLabel(text: "Password di «\(p.name)»")
                Rectangle().fill(Theme.line).frame(height: 1.2)

                Text(previews.filter { !$0.isReadable }.count > 1
                     ? "Questo cassetto è cifrato con un'altra password.\nSe gli altri hanno la stessa, si aprono anche loro."
                     : "Questo cassetto è cifrato con un'altra password.\nScrivila: verrà riscritto con quella di Hush.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                SecureField("Password del file", text: $foreignPassword)
                    .textFieldStyle(PaperFieldStyle())
                    .onSubmit { tentaSblocco(p) }

                if let unlockError {
                    Text(unlockError).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                }

                Spacer(minLength: 0)

                HStack(spacing: 10) {
                    Button("Annulla") { unlocking = nil }
                        .buttonStyle(OutlineButtonStyle())
                    Button(provando ? "Apro…" : "Apri") { tentaSblocco(p) }
                        .buttonStyle(InkButtonStyle(prominent: true))
                        .disabled(foreignPassword.isEmpty || provando)
                        .opacity(foreignPassword.isEmpty || provando ? 0.4 : 1)
                }
            }
            .padding(30)
            .frame(width: 420, height: 300)
            .background(Theme.paper)
            .preferredColorScheme(.light)
        }
    }

    /// Fuori dal thread principale: ogni tentativo è un Argon2id, e provarlo
    /// su più cassetti mentre la finestra aspetta la congelerebbe.
    private func tentaSblocco(_ p: VaultTransfer.Preview) {
        let pw = foreignPassword
        let daProvare = previews
        provando = true
        Task {
            let sbloccati: [VaultTransfer.Preview] = await Task.detached(priority: .userInitiated) {
                // stessa password su tutti: i file di un'importazione vengono
                // quasi sempre dalla stessa installazione
                daProvare.compactMap { VaultTransfer.unlock($0, with: pw) }
            }.value

            provando = false
            guard sbloccati.contains(where: { $0.id == p.id }) else {
                unlockError = "Password sbagliata."
                return
            }
            for aperto in sbloccati {
                if let i = previews.firstIndex(where: { $0.id == aperto.id }) {
                    previews[i] = aperto
                    chosen.insert(aperto.id)
                }
            }
            unlocking = nil
        }
    }

    /// Da dove arriva questo cassetto, detto in due parole.
    private func provenienza(_ p: VaultTransfer.Preview) -> String? {
        switch p.origin {
        case .csv: return "csv"
        case .onePassword: return "1password"
        case .kdbx: return nil
        }
    }

    private func riga(_ p: VaultTransfer.Preview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: p.isReadable ? (chosen.contains(p.id) ? "checkmark.square.fill" : "square")
                                               : "exclamationmark.triangle")
                    .font(.system(size: 13))
                    .foregroundStyle(p.isReadable ? Theme.ink : Theme.danger)

                if let icon = p.icon {
                    Image(systemName: icon).font(.system(size: 12)).foregroundStyle(Theme.ink)
                }
                if let da = provenienza(p) {
                    Text(da)
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().strokeBorder(Theme.line.opacity(0.5), lineWidth: 1))
                }

                Text(p.name.lowercased())
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(p.isReadable ? Theme.ink : Theme.inkSoft)

                Spacer(minLength: 0)

                if let problem = p.problem {
                    Text(problem)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.danger)
                    // se la password ce l'hai, il cassetto non è perso: si
                    // apre e si ricifra con quella delHush
                    if problem.hasPrefix("cifrato") {
                    Button("Ho la password") {
                        unlocking = p
                        foreignPassword = ""
                        unlockError = nil
                    }
                    .buttonStyle(.plain)
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.ink)
                    .underline()
                    }
                } else {
                    Text(p.entries.isEmpty ? "Vuoto" : "\(p.entries.count) voci")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                    if !p.entries.isEmpty {
                        Button {
                            if expanded.contains(p.id) { expanded.remove(p.id) } else { expanded.insert(p.id) }
                        } label: {
                            Image(systemName: expanded.contains(p.id) ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard p.isReadable else { return }
                if chosen.contains(p.id) { chosen.remove(p.id) } else { chosen.insert(p.id) }
            }

            // il contenuto vero: i titoli delle voci dentro al cassetto
            if expanded.contains(p.id) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(p.entries.enumerated()), id: \.offset) { _, title in
                        Text("· \(title.lowercased())")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperRaised)
        .overlay(Rectangle().strokeBorder(p.isReadable ? Theme.line : Theme.danger.opacity(0.5),
                                          lineWidth: 1))
    }
}
