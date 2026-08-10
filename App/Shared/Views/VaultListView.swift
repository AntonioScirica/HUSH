import SwiftUI
import VaultCore

struct VaultListView: View {
    @EnvironmentObject var vm: VaultViewModel
    /// Nella vista classica il lucchetto richiude tutta l'app, non solo lo store.
    var onLock: (() -> Void)?
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
                                saveVault()
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
                saveVault()
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
                if let onLock { onLock() } else { vm.lock() }
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
            // un po' d'aria fra una linguetta e la riga di quella dopo
            .padding(.bottom, 14)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}


/// La schermata di prima del rewrite, richiamabile dalle impostazioni.
/// Due colonne: i progetti nella barra laterale, le voci del progetto
/// scelto a destra. Una voce si apre sul posto, come una fisarmonica.
struct ClassicHomeView: View {
    @EnvironmentObject var vm: VaultViewModel
    let onLock: () -> Void
    /// False finché la porta non si è aperta: la vista sta già lì sotto,
    /// ma i cassetti si caricano solo quando c'è la chiave di sessione.
    var attiva: Bool = true
    /// La barra coi tasti (+, ingranaggio, lucchetto) compare solo a vault
    /// aperto: a porta chiusa quei tasti sarebbero visibili E cliccabili
    /// sopra la porta, perché la barra vive nel livello del titolo.
    var chromeVisibile: Bool = true

    @State private var progetti = VaultFileManager.shared.projects
    @State private var correnteID: String?
    @State private var showSettings = false
    /// La voce aperta nell'accordion (una alla volta).
    @State private var apertaID: UUID?
    @State private var editingEntry: VaultEntry?
    @State private var showEditor = false
    @State private var nuovoProgetto = false
    @State private var nomeProgetto = ""

    #if os(iOS)
    /// Sul telefono la navigazione è a pila: tocchi il progetto e entri.
    @State private var percorso: [String] = []
    #endif

    var body: some View {
        base
        #if os(macOS)
        // niente barra del titolo di sistema: vive SOPRA la porta del
        // caveau e non si può né coprire né dissolvere. Tasti e ricerca
        // stanno nel contenuto, che la porta copre come tutto il resto.
        .toolbar(.hidden, for: .windowToolbar)
        #endif
        .tint(Theme.ink)
        .preferredColorScheme(.light)
        .onAppear { if attiva { carica() } }
        .onChange(of: attiva) { _, on in if on { carica() } }
        .sheet(isPresented: $showEditor) {
            EntryEditorView(entry: editingEntry) { saved in
                if editingEntry != nil {
                    vm.store.updateEntry(saved)
                } else {
                    vm.store.addEntry(saved)
                }
                apertaID = saved.id
                salva()
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            progetti = VaultFileManager.shared.projects
        }) {
            SettingsView(onClose: { showSettings = false }, onImport: {})
                .background(Theme.paper.ignoresSafeArea())
                .preferredColorScheme(.light)
        }
    }

    /// Due colonne sul Mac, pila sul telefono: stessa vista, navigazione
    /// adatta allo schermo che c'è.
    @ViewBuilder
    private var base: some View {
        #if os(iOS)
        NavigationStack(path: $percorso) {
            colonnaProgetti
                .navigationDestination(for: String.self) { _ in
                    listaVoci
                }
        }
        #else
        NavigationSplitView {
            colonnaProgetti
        } detail: {
            listaVoci
        }
        #endif
    }

    // MARK: - Colonne

    private var colonnaProgetti: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                #if os(macOS)
                // tasti nel contenuto, non nella barra di sistema: così la
                // porta del caveau li copre e li scopre insieme al resto
                HStack(spacing: 14) {
                    Spacer(minLength: 0)
                    Button { nomeProgetto = ""; nuovoProgetto = true } label: {
                        Image(systemName: "plus")
                    }
                    .help("Nuovo progetto")
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Impostazioni")
                    Button { onLock() } label: {
                        Image(systemName: "lock")
                    }
                    .help("Blocca")
                }
                .buttonStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink)
                .padding(.bottom, 10)
                #endif

                // il cerca vive qui, sopra il primo progetto: filtra le
                // voci del progetto aperto, mostrate nella colonna accanto
                TextField("cerca…", text: $vm.searchText)
                    .textFieldStyle(PaperFieldStyle())
                    .padding(.bottom, 8)

                ForEach(progetti) { p in
                    let scelto = p.id == correnteID
                    Button {
                        apri(p)
                        #if os(iOS)
                        percorso = [p.id]
                        #endif
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: p.icon ?? "archivebox")
                                .font(.system(size: 12))
                                .frame(width: 16)
                            Text(p.name.lowercased())
                                .font(Theme.mono(12, scelto ? .bold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(scelto ? Theme.paper : Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(scelto ? Theme.ink : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            #if os(macOS)
            // la barra di sistema non c'è più: si lascia spazio ai semafori
            .padding(.top, 34)
            #endif
        }
        #if os(macOS)
        .ignoresSafeArea(edges: .top)
        #endif
        .background(Theme.paper)
        .navigationTitle("progetti")
        // larga abbastanza da mostrare tutti i tasti della barra: più
        // stretta, macOS li nasconde dietro il menu »
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup {
                Button { nomeProgetto = ""; nuovoProgetto = true } label: {
                    Image(systemName: "plus")
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                Button { onLock() } label: {
                    Image(systemName: "lock")
                }
            }
        }
        #endif
        .alert("Nuovo progetto", isPresented: $nuovoProgetto) {
            TextField("nome", text: $nomeProgetto)
            Button("Crea") { creaProgetto() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Un cassetto nuovo, chiuso con la tua master password.")
        }
    }

    /// Crea un progetto vuoto e lo apre: il gemello di "crea progetto"
    /// della parete 3D, per quando la parete non c'è (telefono, elenco).
    private func creaProgetto() {
        let nome = nomeProgetto.trimmingCharacters(in: .whitespaces)
        guard !nome.isEmpty, let chiave = MasterKey.session else { return }
        vm.createNew(name: nome, password: chiave)
        Task { @MainActor in
            guard let bytes = await vm.save() else { return }
            let url = VaultFileManager.shared.freeProjectURL(named: nome)
            try? Data(bytes).write(to: url, options: .atomic)
            try? VaultFileManager.shared.addProject(
                name: nome, url: url,
                icon: VaultTransfer.icona(perNome: nome) ?? "folder",
                noteColor: "#FADA5C"
            )
            progetti = VaultFileManager.shared.projects
            if let creato = progetti.first(where: { $0.path == url.path }) {
                apri(creato)
            }
        }
    }

    private var listaVoci: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // intestazione: nome del progetto a sinistra, "+" a destra
                HStack {
                    Text((progetti.first { $0.id == correnteID }?.name ?? "").lowercased())
                        .font(Theme.mono(13, .bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        editingEntry = nil
                        showEditor = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("nuova voce")
                        }
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .fixedSize()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 14)

                ForEach(Array(vm.filteredEntries.enumerated()), id: \.element.id) { index, entry in
                    let aperta = apertaID == entry.id
                    EntryTabRow(
                        entry: entry,
                        number: index + 1,
                        alignment: index.isMultiple(of: 2) ? .leading : .trailing,
                        selected: aperta
                    ) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            apertaID = aperta ? nil : entry.id
                        }
                    }
                    .contextMenu {
                        Button("Modifica") {
                            editingEntry = entry
                            showEditor = true
                        }
                        Button("Elimina", role: .destructive) { elimina(entry) }
                    }

                    // le credenziali si aprono qui sotto, non di lato
                    if aperta {
                        EntryInlineDetail(
                            entry: entry,
                            onEdit: {
                                editingEntry = entry
                                showEditor = true
                            },
                            onDelete: { elimina(entry) }
                        )
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Theme.line).frame(height: 1.1)
                        }
                        // niente .move: la scivolata dall'alto sembrava
                        // la voce che arriva da fuori, non che si apre
                        .transition(.opacity)
                    }
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 10)
        }
        #if os(macOS)
        // la barra sopra questa colonna non ha tasti: era solo vuoto,
        // il contenuto può salire fin quasi al bordo della finestra
        .ignoresSafeArea(edges: .top)
        #endif
        .background(Theme.paper)
        #if os(iOS)
        .searchable(text: $vm.searchText, prompt: "cerca…")
        #endif
        .navigationTitle("")
        .overlay {
            if vm.filteredEntries.isEmpty {
                VStack(spacing: 8) {
                    Text(vm.searchText.isEmpty ? "cassetto vuoto" : "nessun risultato")
                        .font(Theme.mono(13, .semibold))
                    Text(vm.searchText.isEmpty ? "aggiungi la prima voce con +" : "prova un altro termine")
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)
                }
                .foregroundStyle(Theme.ink)
            }
        }
    }

    // MARK: - Dati

    private func carica() {
        progetti = VaultFileManager.shared.projects
        let corrente = progetti.first { $0.path == VaultFileManager.shared.currentPath }
            ?? progetti.first
        if let corrente { apri(corrente) }
    }

    /// Apre un progetto nello store della vista classica. Prima si chiude la
    /// libreria della parete 3D: due copie dello stesso vault in memoria si
    /// sovrascriverebbero a vicenda.
    private func apri(_ p: VaultFileManager.Project) {
        guard let chiave = MasterKey.session else { return }
        correnteID = p.id
        apertaID = nil
        vm.searchText = ""
        Task { @MainActor in
            VaultLibrary.shared.closeAll(progetti)
            try? VaultFileManager.shared.selectProject(p)
            if let bytes = try? VaultFileManager.shared.readVault() {
                await vm.open(fileData: bytes, password: chiave)
            }
        }
    }

    private func elimina(_ entry: VaultEntry) {
        if apertaID == entry.id { apertaID = nil }
        vm.store.deleteEntry(id: entry.id)
        salva()
    }

    /// Ogni modifica finisce su disco da sola, come nella parete 3D.
    private func salva() {
        Task {
            guard let bytes = await vm.save() else { return }
            try? VaultFileManager.shared.writeVault(bytes)
        }
    }
}
