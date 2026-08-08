import SwiftUI
import VaultCore

struct EntryEditorView: View {
    @EnvironmentObject var vm: VaultViewModel
    @Environment(\.dismiss) private var dismiss

    let entry: VaultEntry?
    let onSave: (VaultEntry) -> Void

    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var url = ""
    @State private var notes = ""
    @State private var showPassword = false
    @State private var showDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                IndexLabel(number: entry == nil ? 4 : 5, text: entry == nil ? "nuova voce" : "modifica voce")
                    .padding(.bottom, 2)

                TextField("titolo", text: $title)
                    .textFieldStyle(PaperFieldStyle())
                TextField("utente / email", text: $username)
                    .textFieldStyle(PaperFieldStyle())
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                HStack(spacing: 8) {
                    Group {
                        if showPassword {
                            TextField("password", text: $password)
                        } else {
                            SecureField("password", text: $password)
                        }
                    }
                    .textFieldStyle(PaperFieldStyle())
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.ink)
                    Button { password = PasswordGenerator.generate(.init()) } label: {
                        Image(systemName: "dice")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.ink)
                }

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

                TextField("url", text: $url)
                    .textFieldStyle(PaperFieldStyle())
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                TextField("note", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(PaperFieldStyle())

                HStack(spacing: 10) {
                    Button("annulla") { dismiss() }
                        .buttonStyle(OutlineButtonStyle())
                        .frame(width: 110)
                    Button("salva") { save() }
                        .buttonStyle(InkButtonStyle(prominent: true))
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                }
                .padding(.top, 8)

                if entry != nil {
                    Button("elimina voce") { showDeleteConfirm = true }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.danger)
                        .padding(.top, 4)
                }
            }
            .padding(26)
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
        .onAppear {
            if let entry {
                title = entry.title; username = entry.username; password = entry.password
                url = entry.url; notes = entry.notes
            }
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
        var e = entry ?? VaultEntry(title: title)
        e.title = title
        e.username = username
        e.password = password
        e.url = url
        e.notes = notes
        e.modified = Date()
        onSave(e)
        dismiss()
    }
}
