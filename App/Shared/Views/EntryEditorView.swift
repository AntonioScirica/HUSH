import SwiftUI
import VaultCore

/// Editor delle voci per la vista a elenco (Mac) e per il telefono: le
/// stesse categorie della parete 3D — accesso, password, nota, carta,
/// identità — con i campi giusti per ognuna.
struct EntryEditorView: View {
    @EnvironmentObject var vm: VaultViewModel
    @Environment(\.dismiss) private var dismiss

    let entry: VaultEntry?
    let onSave: (VaultEntry) -> Void

    /// Un campo libero in modifica: etichetta fissa, valore editabile.
    private struct Campo: Identifiable {
        let id = UUID()
        var label: String
        var value: String
        var multiline = false
    }

    @State private var kind: EntryKind = .login
    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var campi: [Campo] = []
    @State private var showPassword = false
    @State private var showDeleteConfirm = false

    /// Il documento vive sulla parete del Mac (serve l'allegato cifrato):
    /// qui si può modificare una voce documento esistente, non crearne.
    private var categorieDisponibili: [EntryKind] {
        [.login, .password, .secureNote, .card, .identity]
    }

    private var conCredenziali: Bool { kind == .login || kind == .password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                IndexLabel(text: entry == nil ? "nuova voce · \(kind.label)" : "modifica voce")
                    .padding(.bottom, 2)

                // la categoria si sceglie solo alla nascita: cambiarla a una
                // voce esistente scombinerebbe i campi già salvati
                if entry == nil {
                    HStack(spacing: 8) {
                        ForEach(categorieDisponibili, id: \.rawValue) { c in
                            Button {
                                kind = c
                                preparaCampi()
                            } label: {
                                Image(systemName: c.icon)
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(kind == c ? Theme.ink : Theme.paperRaised)
                                    .foregroundStyle(kind == c ? Theme.paper : Theme.ink)
                                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(c.label)
                        }
                    }
                }

                TextField("titolo", text: $title)
                    .textFieldStyle(PaperFieldStyle())

                if conCredenziali {
                    if kind == .login {
                        TextField("utente / email", text: $username)
                            .textFieldStyle(PaperFieldStyle())
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            #endif
                    }

                    HStack(spacing: 8) {
                        Group {
                            if showPassword {
                                TextField("password", text: $password)
                            } else {
                                SecureField("password", text: $password)
                            }
                        }
                        .textFieldStyle(.plain)
                        .font(Theme.mono(13))
                        // SecureField e TextField hanno metriche interne
                        // leggermente diverse: senza altezza fissa il campo
                        // "respira" un pelo passando dall'una all'altra
                        .frame(height: 18)

                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.ink)

                        Button { password = PasswordGenerator.generate(.init()) } label: {
                            Image(systemName: "dice")
                                .frame(width: 16, height: 16)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.ink)
                    }
                    .padding(10)
                    .background(Theme.paperRaised)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

                    if !password.isEmpty {
                        let strength = PasswordGenerator.strength(of: password)
                        HStack(spacing: 5) {
                            ForEach(0..<4) { i in
                                Rectangle()
                                    .fill(i < strength.rawValue ? strengthColor(strength) : Theme.line.opacity(0.25))
                                    .frame(height: 4)
                            }
                        }
                        Text("robustezza: \(strength.label.lowercased())")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                    }

                    if kind == .login {
                        TextField("url", text: $url)
                            .textFieldStyle(PaperFieldStyle())
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }
                    TextField("note", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(PaperFieldStyle())
                } else {
                    // nota, carta, identità (e documento esistente): campi
                    // liberi con la loro etichetta, come sulla parete
                    ForEach($campi) { $campo in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(campo.label.uppercased())
                                .font(Theme.mono(9, .semibold))
                                .tracking(1.5)
                                .foregroundStyle(Theme.inkSoft)
                            if campo.multiline {
                                TextField("", text: $campo.value, axis: .vertical)
                                    .lineLimit(3...8)
                                    .textFieldStyle(PaperFieldStyle())
                            } else {
                                TextField("", text: $campo.value)
                                    .textFieldStyle(PaperFieldStyle())
                            }
                        }
                    }
                }

            }
            .padding(26)
        }
        // le CTA stanno SEMPRE in fondo alla finestra, fuori dallo
        // scorrimento: coi campi corti non salgono a metà, coi campi
        // lunghi non scappano sotto
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button("annulla") { dismiss() }
                        .buttonStyle(OutlineButtonStyle())
                        .frame(maxWidth: .infinity)
                    Button("salva") { save() }
                        .buttonStyle(InkButtonStyle(prominent: true))
                        .frame(maxWidth: .infinity)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }

                if entry != nil {
                    Button("elimina voce") { showDeleteConfirm = true }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 22)
            .padding(.top, 10)
            .background(Theme.paper)
        }
        .frame(minWidth: 420, minHeight: 440)
        .background(Theme.paper)
        .preferredColorScheme(.light)
        .confirmationDialog("Eliminare questa voce?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Elimina", role: .destructive) {
                if let entry { vm.store.deleteEntry(id: entry.id) }
                dismiss()
            }
            Button("Annulla", role: .cancel) {}
        }
        .onAppear { carica() }
    }

    // MARK: - Dati

    private func carica() {
        guard let entry else {
            preparaCampi()
            return
        }
        kind = EntryKind(rawValue: EntryMapping.kind(of: entry)) ?? .login
        title = entry.title
        if conCredenziali {
            username = entry.username; password = entry.password
            url = entry.url; notes = entry.notes
        } else {
            campi = EntryMapping.details(of: entry).map {
                Campo(label: $0.label, value: $0.value,
                      multiline: $0.label.lowercased().hasPrefix("nota") || $0.label.lowercased() == "note")
            }
            if campi.isEmpty { preparaCampi() }
        }
    }

    /// Le righe di partenza per una voce nuova, categoria per categoria:
    /// le stesse etichette che usa la parete, così i vault restano uguali.
    private func preparaCampi() {
        guard entry == nil else { return }
        switch kind {
        case .login, .password, .document:
            campi = []
        case .secureNote:
            campi = [Campo(label: "nota", value: "", multiline: true)]
        case .card:
            campi = [
                Campo(label: "intestatario", value: ""),
                Campo(label: "numero carta", value: ""),
                Campo(label: "scadenza", value: ""),
                Campo(label: "cvv", value: ""),
                Campo(label: "pin", value: ""),
                Campo(label: "note", value: "", multiline: true),
            ]
        case .identity:
            campi = [
                Campo(label: "nome", value: ""),
                Campo(label: "cognome", value: ""),
                Campo(label: "indirizzo", value: ""),
                Campo(label: "telefono", value: ""),
                Campo(label: "email", value: ""),
                Campo(label: "note", value: "", multiline: true),
            ]
        }
    }

    private func strengthColor(_ s: PasswordGenerator.Strength) -> Color {
        switch s {
        case .weak: return Theme.danger
        case .fair: return .orange
        case .good: return Theme.yellow
        case .excellent: return .green
        }
    }

    private func save() {
        var e: VaultEntry
        if conCredenziali {
            // in modifica si tocca solo il canonico: i campi extra (secondi
            // url, campi personalizzati) restano come sono
            e = entry ?? EntryMapping.credentialEntry(
                kind: kind.rawValue, title: title, user: username,
                password: password, url: url, notes: notes, extras: []
            )
            e.title = title
            e.username = username
            e.password = password.isEmpty && entry == nil ? PasswordGenerator.generate(.init()) : password
            e.url = url
            e.notes = notes
        } else {
            let compilati = campi
                .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { (label: $0.label, value: $0.value) }
            if let entry {
                // i campi di servizio (allegati e simili) si riportano
                // intatti, o risalvando si perderebbe il documento
                e = entry
                e.title = title
                e.customFields = [VaultCustomField(key: EntryMapping.kindKey, value: kind.rawValue)]
                    + EntryMapping.hiddenFields(of: entry)
                    + compilati.map {
                        VaultCustomField(key: $0.label, value: $0.value,
                                         isProtected: EntryMapping.isSecret($0.label))
                    }
            } else {
                e = EntryMapping.detailEntry(kind: kind.rawValue, title: title, fields: compilati)
            }
        }
        e.modified = Date()
        onSave(e)
        dismiss()
    }
}
