import SwiftUI
import VaultCore

struct EntryDetailView: View {
    @EnvironmentObject var vm: VaultViewModel
    let entry: VaultEntry
    let onEdit: () -> Void

    @State private var revealPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Intestazione stile "VERONICA ZHANG HEADQUARTERS":
                // barra nera con il titolo in negativo.
                HStack(spacing: 0) {
                    Text(entry.title.isEmpty ? "SENZA TITOLO" : entry.title.uppercased())
                        .font(Theme.mono(18, .bold))
                        .tracking(2)
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.ink)
                    Spacer()
                }
                .padding(.bottom, 4)

                if !entry.groupPath.isEmpty {
                    Text(entry.groupPath.lowercased())
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .padding(.bottom, 8)
                }

                DottedDivider().padding(.vertical, 12)

                VStack(spacing: 0) {
                    if !entry.username.isEmpty {
                        FieldRow(label: "utente", value: entry.username) {
                            vm.copyToClipboard(entry.username, label: "Utente")
                        }
                    }
                    FieldRow(label: "password", value: revealPassword ? entry.password : String(repeating: "•", count: 12), monospacedValue: true) {
                        vm.copyToClipboard(entry.password, label: "Password")
                    } trailing: {
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.borderless)
                    }
                    if !entry.url.isEmpty {
                        FieldRow(label: "url", value: entry.url) {
                            vm.copyToClipboard(entry.url, label: "URL")
                        }
                    }
                }
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))

                if !entry.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOTE")
                            .font(Theme.mono(10, .semibold))
                            .tracking(2)
                            .foregroundStyle(Theme.inkSoft)
                        Text(entry.notes)
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))
                    .padding(.top, 14)
                }

                Button("modifica") { onEdit() }
                    .buttonStyle(InkButtonStyle())
                    .frame(width: 160)
                    .padding(.top, 18)
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .navigationTitle("")
        .onDisappear { revealPassword = false }
    }
}

/// Le stesse credenziali, ma dentro la riga: è il pannello che si apre
/// sotto la linguetta nell'accordion della vista a elenco.
struct EntryInlineDetail: View {
    @EnvironmentObject var vm: VaultViewModel
    let entry: VaultEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var revealPassword = false
    /// Indici dei campi segreti momentaneamente in chiaro.
    @State private var svelati: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                if !entry.username.isEmpty {
                    FieldRow(label: "utente", value: entry.username) {
                        vm.copyToClipboard(entry.username, label: "Utente")
                    }
                }
                // la password c'è solo nelle voci con credenziali: per carte,
                // note e identità mostrarla vorrebbe dire una riga di puntini
                // che svelata è vuota
                if !entry.password.isEmpty {
                    FieldRow(label: "password", value: revealPassword ? entry.password : String(repeating: "•", count: 12), monospacedValue: true) {
                        vm.copyToClipboard(entry.password, label: "Password")
                    } trailing: {
                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if !entry.url.isEmpty {
                    FieldRow(label: "url", value: entry.url) {
                        vm.copyToClipboard(entry.url, label: "URL")
                    }
                }
                // i campi liberi: numero carta, cvv, nome e cognome, note
                // sicure — quelli segreti spuntinati, con occhio per svelarli
                ForEach(Array(EntryMapping.details(of: entry).enumerated()), id: \.offset) { i, campo in
                    if EntryMapping.isSecret(campo.label) {
                        FieldRow(label: campo.label,
                                 value: svelati.contains(i) ? campo.value : String(repeating: "•", count: max(campo.value.count, 6)),
                                 monospacedValue: true) {
                            vm.copyToClipboard(campo.value, label: campo.label.capitalized)
                        } trailing: {
                            Button {
                                if svelati.contains(i) { svelati.remove(i) } else { svelati.insert(i) }
                            } label: {
                                Image(systemName: svelati.contains(i) ? "eye.slash" : "eye")
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.borderless)
                        }
                    } else {
                        FieldRow(label: campo.label, value: campo.value) {
                            vm.copyToClipboard(campo.value, label: campo.label.capitalized)
                        }
                    }
                }
            }
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))

            if !entry.notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("NOTE")
                        .font(Theme.mono(10, .semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.inkSoft)
                    Text(entry.notes)
                        .font(Theme.mono(12))
                        .foregroundStyle(Theme.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))
                .padding(.top, 12)
            }

            HStack(spacing: 10) {
                Button("modifica") { onEdit() }
                    .buttonStyle(InkButtonStyle())
                    .frame(maxWidth: .infinity)
                Button("elimina") { onDelete() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .onDisappear { revealPassword = false; svelati = [] }
    }
}

/// Riga campo tipo modulo cartaceo: etichetta mono minuscola sopra, valore
/// sotto, azioni a destra; righe separate da hairline.
private struct FieldRow<Trailing: View>: View {
    let label: String
    let value: String
    var monospacedValue: Bool = false
    let onCopy: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    init(label: String, value: String, monospacedValue: Bool = false, onCopy: @escaping () -> Void, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.label = label
        self.value = value
        self.monospacedValue = monospacedValue
        self.onCopy = onCopy
        self.trailing = trailing
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label.uppercased())
                        .font(Theme.mono(9, .semibold))
                        .tracking(2)
                        .foregroundStyle(Theme.inkSoft)
                    Text(value)
                        .font(Theme.mono(13, monospacedValue ? .semibold : .regular))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                }
                Spacer()
                trailing()
                    .foregroundStyle(Theme.ink)
                Button { onCopy() } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.ink)
            }
            .padding(12)
            Rectangle().fill(Theme.line.opacity(0.5)).frame(height: 1)
        }
    }
}

/// Divisore puntinato come i bordi tratteggiati della reference.
struct DottedDivider: View {
    var body: some View {
        Line()
            .stroke(style: StrokeStyle(lineWidth: 1.2, dash: [2, 4]))
            .foregroundStyle(Theme.line)
            .frame(height: 1.2)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}
