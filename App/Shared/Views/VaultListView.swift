import SwiftUI
import VaultCore

struct VaultListView: View {
    @EnvironmentObject var vm: VaultViewModel
    @State private var selectedEntry: VaultEntry?
    @State private var showEditor = false
    @State private var editingEntry: VaultEntry?
    @State private var showGenerator = false
    @State private var showExporter = false
    @State private var exportDocument = KdbxDocument()
    @State private var localError: String?

    var body: some View {
        NavigationSplitView {
            ScrollView {
                LazyVStack(spacing: 0) {
                    Button {
                        editingEntry = nil
                        showEditor = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text("nuova voce")
                        }
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)

                    ForEach(Array(vm.filteredEntries.enumerated()), id: \.element.id) { index, entry in
                        EntryTabRow(
                            entry: entry,
                            number: index + 1,
                            alignment: index.isMultiple(of: 2) ? .leading : .trailing,
                            selected: selectedEntry?.id == entry.id
                        ) {
                            selectedEntry = entry
                        }
                        .contextMenu {
                            Button("Modifica") {
                                selectedEntry = entry
                                editingEntry = entry
                                showEditor = true
                            }
                            Button("Elimina", role: .destructive) {
                                if selectedEntry?.id == entry.id { selectedEntry = nil }
                                vm.store.deleteEntry(id: entry.id)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 4)
            }
            .background(Theme.paper)
            .searchable(text: $vm.searchText, prompt: "cerca…")
            .navigationTitle(vm.vaultName)
            .navigationSplitViewColumnWidth(min: 250, ideal: 300)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) { toolbarButtons }
                #else
                ToolbarItemGroup { toolbarButtons }
                #endif
            }
            .overlay {
                if vm.filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Text(vm.searchText.isEmpty ? "vault vuoto" : "nessun risultato")
                            .font(Theme.mono(13, .semibold))
                        Text(vm.searchText.isEmpty ? "aggiungi la prima voce con +" : "prova un altro termine")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .foregroundStyle(Theme.ink)
                }
            }
        } detail: {
            Group {
                if let selectedEntry, vm.store.allEntries.contains(where: { $0.id == selectedEntry.id }) {
                    EntryDetailView(entry: selectedEntry, onEdit: {
                        editingEntry = selectedEntry
                        showEditor = true
                    })
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "key.horizontal")
                            .font(.system(size: 28))
                        Text("seleziona una voce")
                            .font(Theme.mono(12))
                    }
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.paper)
                }
            }
        }
        .tint(Theme.ink)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showEditor) {
            EntryEditorView(entry: editingEntry) { saved in
                if editingEntry != nil {
                    vm.store.updateEntry(saved)
                } else {
                    vm.store.addEntry(saved)
                }
                selectedEntry = saved
            }
        }
        .sheet(isPresented: $showGenerator) {
            GeneratorView()
        }
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .kdbx, defaultFilename: vm.vaultName) { result in
            if case .success(let url) = result {
                try? VaultFileManager.shared.rememberVaultLocation(url)
            }
        }
        .alert("Errore", isPresented: .constant(localError != nil), actions: {
            Button("OK") { localError = nil }
        }, message: { Text(localError ?? "") })
        .onAppear { vm.resetAutolockTimer() }
    }

    private var toolbarButtons: some View {
        HStack {
            Button {
                showGenerator = true
            } label: {
                Image(systemName: "dice")
            }
            .help("Generatore password")

            Button {
                saveVault()
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .help("Salva vault")

            Button {
                vm.lock()
            } label: {
                Image(systemName: "lock")
            }
            .help("Blocca")
        }
    }

    private func saveVault() {
        Task {
            guard let bytes = await vm.save() else { return }
            if VaultFileManager.shared.hasVault {
                do {
                    try VaultFileManager.shared.writeVault(bytes)
                } catch {
                    localError = "Salvataggio non riuscito: \(error.localizedDescription)"
                }
            } else {
                exportDocument = KdbxDocument(bytes: bytes)
                showExporter = true
            }
        }
    }
}

/// Riga-divider: linguetta con numero + titolo appoggiata su una riga continua.
/// Le linguette si alternano a sinistra/destra come nelle reference.
private struct EntryTabRow: View {
    let entry: VaultEntry
    let number: Int
    let alignment: HorizontalAlignment
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack {
                    if alignment == .trailing { Spacer(minLength: 0) }
                    HStack(spacing: 12) {
                        Text(String(format: "%03d", number))
                            .font(Theme.mono(12))
                            .foregroundStyle(selected ? Theme.paper.opacity(0.65) : Theme.inkSoft)
                        Text(entry.title.isEmpty ? "senza titolo" : entry.title.lowercased())
                            .font(Theme.mono(13, selected ? .bold : .regular))
                            .lineLimit(1)
                            .foregroundStyle(selected ? Theme.paper : Theme.ink)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(TabShape().fill(selected ? Theme.ink : Theme.paperRaised))
                    .overlay(TabShape().stroke(Theme.line, lineWidth: 1.1))
                    if alignment == .leading { Spacer(minLength: 0) }
                }
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1.1)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}
