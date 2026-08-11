#if os(macOS)
import SwiftUI
import AppKit
import VaultCore

/// Copia negli appunti con un click: i campi si vedono solo in sola lettura
/// finché non premi "modifica", quindi copiarli deve essere immediato.
///
/// La copia si cancella da sola dopo il tempo scelto nelle impostazioni: una
/// password lasciata negli appunti la legge qualunque cosa incolli dopo. Si
/// svuota solo se nel frattempo non hai copiato altro, per non portarti via
/// roba che non è nostra.
private func copyToClipboard(_ text: String) {
    guard !text.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    // "concealed": la convenzione con cui i gestori di appunti e la
    // Universal Clipboard capiscono di non dover conservare né sincronizzare
    // il valore. Senza, la password finiva nella cronologia degli appunti e
    // sugli altri dispositivi, dove restava anche dopo che l'app l'aveva
    // cancellata da qui.
    pb.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    pb.setString(text, forType: .string)

    let seconds = Preferences.clipboardSeconds
    guard seconds > 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) {
        if NSPasteboard.general.string(forType: .string) == text {
            NSPasteboard.general.clearContents()
        }
    }
}

/// Campo che prende il fuoco da solo appena compare. Deve essere una view a
/// sé: un @FocusState dichiarato nella view che *presenta* la sheet non
/// governa il contenuto della sheet (finestra diversa), ed è il motivo per
/// cui l'autofocus non partiva mai.
private struct AutoFocusField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(PaperFieldStyle())
            .focused($focused)
            .onAppear {
                // un attimo dopo: la finestra della sheet deve prima
                // diventare key, o l'assegnazione non attacca
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
            }
    }
}

private struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            copyToClipboard(text)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { copied = false }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(copied ? Theme.ink : Theme.inkSoft)
                // misura fissa: le due icone hanno ingombri diversi e la
                // riga cambiava larghezza E altezza al momento della copia
                .frame(width: 14, height: 14)
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
    }
}

/// Home: parete di cassetti in 3D vero (DrawerWall3D) — un cassetto per
/// progetto (vault separato). Click sul centrale: il cassetto scorre fuori
/// e la camera si avvicina, mostrando le cartelle (le password) dentro.
struct ProjectsHomeView: View {
    /// Richiude il caveau e riporta alla porta.
    var onLock: () -> Void = {}
    /// A scrigno chiuso la parete si vede lo stesso, attraverso il vano della
    /// porta: i comandi però restano nascosti finché non si è entrati.
    var chromeVisible = true
    /// Aperto da fuori (dalla striscia della prova).
    var showSettingsSignal: Binding<Bool>? = nil

    @EnvironmentObject var vm: VaultViewModel

    @State private var projects: [VaultFileManager.Project] = VaultFileManager.shared.projects
    /// Cella con il cassetto aperto — resta lì dov'è, non si sposta mai al centro.
    @State private var openCell: Int?
    private var drawerOpen: Bool { openCell != nil }
    @State private var searchText = ""
    /// Cartella da selezionare appena il cassetto scelto dalla ricerca ha
    /// finito di aprirsi: impostarla insieme a openCell non funzionava,
    /// l'onChange di openCell la azzerava subito.
    @State private var searchPendingFolder: Int?
    /// Cartella estratta al centro (1-based nel cassetto; voce = indice - 1).
    @State private var selectedFolder: Int?
    /// Cartella appena creata: si alza sola, senza estrarsi (niente card).
    @State private var revealFolder: Int?
    /// Rettangolo a schermo del corpo della cartella estratta (dalla scena 3D).
    @State private var folderRect: CGRect?
    /// "Nuova password" con più progetti: scegli in quale metterla.
    @State private var showProjectPicker = false
    /// Creazione progetto: cella target, targhetta proiettata, nome digitato.
    @State private var creatingCell: Int?
    @State private var plateRect: CGRect?
    @State private var createName = ""
    @FocusState private var plateNameFocused: Bool

    @State private var showCreate = false
    @State private var newName = ""
    @State private var newPassword = ""
    @State private var newIcon: String?
    @State private var newNoteColor: String? = ProjectsHomeView.noteColors.first
    /// Modalità modifica di un progetto esistente (vs creazione).
    @State private var isEditingProject = false
    @State private var editingProjectID: String?
    @State private var showDeleteConfirm = false
    @State private var showDeleteEntryConfirm = false
    /// Zoom ravvicinato sul post-it, per icona e colore.
    @State private var focusNote = false
    @State private var noteRect: CGRect?
    @State private var revealNewPassword = false
    @State private var showIconLibrary = false
    @State private var iconSearch = ""

    /// Scorciatoie sempre visibili + libreria completa dietro al picker
    /// (stile Lucide — SF Symbols è l'equivalente nativo Apple, stesso
    /// linguaggio a contorno sottile, zero dipendenze in più).
    private let iconQuickPicks = [
        "folder", "lock", "creditcard", "person.2", "briefcase",
        "house", "globe", "gamecontroller", "cart", "airplane"
    ]
    private let iconLibrary = [
        "folder", "lock", "lock.shield", "key", "creditcard", "banknote",
        "person", "person.2", "person.3", "briefcase", "building.2",
        "house", "globe", "network", "wifi", "server.rack", "externaldrive",
        "gamecontroller", "cart", "bag", "airplane", "car", "bus", "tram",
        "heart", "graduationcap", "book", "music.note", "headphones",
        "camera", "photo", "video", "film", "tv", "gift", "cup.and.saucer",
        "fork.knife", "leaf", "pawprint", "figure.walk", "bicycle",
        "envelope", "phone", "message", "bubble.left.and.bubble.right",
        "at", "paperplane", "doc.text", "folder.badge.gearshape",
        "calendar", "clock", "alarm", "bell", "flag", "star",
        "bolt", "sun.max", "moon", "cloud", "umbrella", "flame",
        "drop", "hare", "tortoise", "ant", "fish", "leaf.fill",
        "cross.case", "pills", "stethoscope", "bandage", "figure.run",
        "dumbbell", "sportscourt", "trophy", "ticket", "theatermasks",
        "paintpalette", "hammer", "wrench.and.screwdriver", "gearshape",
        "printer", "desktopcomputer", "laptopcomputer", "keyboard",
        "display", "shippingbox", "cube", "archivebox", "tray",
        "cart.badge.plus", "banknote.fill", "chart.bar", "chart.pie",
        "dollarsign.circle", "eurosign.circle", "sterlingsign.circle",
        "building.columns", "shield", "checkmark.shield", "eye",
        "faceid", "touchid", "qrcode", "barcode", "tag", "bookmark"
    ]

    @State private var openingProject: VaultFileManager.Project?
    @State private var openPassword = ""
    @State private var pendingOpenData: [UInt8]?
    @State private var showOpenPasswordSheet = false

    @State private var localError: String?
    @State private var showSettings = false
    /// Tour guidato sulla parete vuota: nasce già "done" se l'hai già visto.
    @State private var tourStep: TourStep = Preferences.vistoAiutoParete ? .done : .creaCassetto
    /// L'ultima tappa vera vista, per poterla ancora disegnare mentre si
    /// dissolve dopo che tourStep è già passato a .done.
    @State private var tourDisplayStep: TourStep = Preferences.vistoAiutoParete ? .done : .creaCassetto
    @State private var creaButtonRect: CGRect = .zero
    @State private var iconButtonRect: CGRect = .zero
    @State private var salvaIconaRect: CGRect = .zero
    @State private var creaProgettoRect: CGRect = .zero
    /// La primissima volta (tour attivo) la chrome compare più svelta: con
    /// la dissolvenza lunga normale c'era il tempo di cliccare qualcosa
    /// prima ancora che il fumetto arrivasse a spiegare cosa fare.
    private var chromeAppearDuration: Double { tourStep != .done ? 0.5 : 1.6 }

    // ponytail: voci finte solo per prototipare l'apertura del cassetto —
    // da sostituire con vm.store.allEntries quando il vault reale è collegato qui.
    // Una lista per progetto: un cassetto nuovo parte vuoto, non eredita
    // quelle di un altro (prima era un unico array condiviso da tutti).
    /// Un solo sheet per tutto il flusso "nuova voce": passare da categoria
    /// a modulo cambia solo `entryStep`, non chiude/riapre un secondo sheet
    /// — quello causava un frame con la categoria vecchia prima di aggiornarsi.
    @State private var showEntryFlow = false
    /// Tendina del progetto aperta dentro il modulo.
    @State private var showEntryProjectList = false
    private enum EntryFlowStep { case pickType, form }
    @State private var entryStep: EntryFlowStep = .pickType
    @State private var newEntryKind: EntryKind = .login
    @State private var newEntryProjectID: String?
    @State private var newEntryName = ""
    @State private var newEntryUser = ""
    @State private var newEntryPassword = ""
    @State private var newEntryURLs: [IdentifiedString] = [IdentifiedString()]
    /// "nota sicura": più note, ognuna col suo titolo (label) e il suo testo
    /// (value) — dentro una cartella "documenti" ci stanno appunti diversi,
    /// e senza un titolo per ciascuno non si distinguono.
    @State private var newSecureNotes: [CustomField] = [CustomField()]
    @State private var newEntryFields: [CustomField] = []
    @State private var newEntryNotes = ""
    @State private var revealNewEntryPassword = false
    @State private var newEntryScrolled = false
    @State private var newEntryAtBottom = true
    /// Col campo password a fuoco, il dado si accende.
    @FocusState private var newEntryPasswordFocused: Bool
    // campi delle voci "carta di credito" e "identità" — mostrati solo per
    // il tipo giusto, tutto il resto (progetto, titolo, note) è condiviso
    @State private var newCardHolder = ""
    @State private var newCardNumber = ""
    @State private var newCardExpiry = ""
    @State private var newCardCVV = ""
    @State private var newCardPIN = ""
    @State private var newIdentityFirstName = ""
    @State private var newIdentityLastName = ""
    @State private var newIdentityAddress = ""
    @State private var newIdentityPhone = ""
    @State private var newIdentityEmail = ""
    // "documento": file scelto dall'utente, copiato negli allegati dell'app
    // solo alla creazione (così annullare non lascia file orfani in giro)
    @State private var showDocumentImporter = false
    @State private var pendingDocumentURL: URL?

    /// Campo extra libero (stile 1Password): etichetta + valore, testo o
    /// mascherato come una password.
    struct CustomField: Identifiable {
        let id = UUID()
        var label = ""
        var value = ""
        var isSecret = false
    }

    /// Stringa con identità stabile, per liste editabili (ForEach + Binding)
    /// dove il valore stesso non basta a distinguere le righe.
    struct IdentifiedString: Identifiable {
        let id = UUID()
        var value = ""
    }

    // Parete molto più grande di quel che la camera inquadra (5×5): coi
    // margini che strabordano e la parallasse sembra continuare all'infinito.
    private let cols = WallLayout.cols
    private let rows = WallLayout.rows
    private let visibleCols = WallLayout.visibleCols
    private let visibleRows = WallLayout.visibleRows
    private var centerIndex: Int { WallLayout.centerIndex }

    /// Celle ordinate per distanza dal centro (il centro incluso per primo):
    /// dove finiscono i progetti, in ordine di creazione — fisso, non dipende
    /// da quale cassetto è aperto, così aprirne uno non sposta gli altri.
    private var spiralOrder: [Int] { WallLayout.spiralOrder }

    /// Cella → progetto che la occupa, in ordine di creazione (stabile).
    private var projectAtCell: [Int: VaultFileManager.Project] {
        WallLayout.projectAtCell(projects)
    }

    private func cellIndex(for project: VaultFileManager.Project) -> Int? {
        WallLayout.cellIndex(of: project, in: projects)
    }

    /// Progetto del cassetto attualmente aperto (se aperto).
    private var openProjectEntry: VaultFileManager.Project? {
        openCell.flatMap { projectAtCell[$0] }
    }

    /// Etichetta di sezione dentro i moduli: maiuscoletto spaziato, grigio.
    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(10, .semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSoft)
    }

    /// Bottoncino d'angolo, stesso tratto della barra centrale.
    private func cornerButton(_ icon: String, help: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 42, height: 42)
                .background(Theme.paper)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// Righe di dati della voce selezionata: da queste dipende quanto deve
    /// crescere il corpo della cartella estratta.
    private var selectedEntryRows: Int {
        guard let entry = selectedEntry else { return 3 }
        switch kind(of: entry) {
        case .login, .password:
            // utente + password + url + note (in modifica c'è sempre) + extra
            return 4 + EntryMapping.details(of: entry).count
        default:
            return max(1, EntryMapping.details(of: entry).count)
        }
    }

    /// Altezza del corpo della cartella: dipende SOLO dai dati della voce,
    /// mai dallo stato modifica. Cambiarla al volo significa ricostruire la
    /// geometria a metà scena — uno scatto secco, impossibile da animare.
    /// Meglio nascere già larga abbastanza per entrambi gli stati.
    private var folderBodyHeight: CGFloat {
        let base = DrawerWall3D.folderExtractedMinH
        var h = base + CGFloat(selectedEntryRows - 3) * 0.13
        if isSelectedEntryEditable { h += 0.18 }  // i campi input sono più alti
        return min(DrawerWall3D.folderMaxBodyH, max(base, h))
    }

    /// Le sole voci con editor in-place (le altre sono in sola lettura).
    private var isSelectedEntryEditable: Bool {
        guard let entry = selectedEntry else { return false }
        let k = kind(of: entry)
        return k == .login || k == .password
    }

    /// Riscrive una voce nel suo vault. L'archivio segna il progetto come da
    /// salvare e ci pensa lui a mettere su disco, poco dopo.
    private func saveEdits(to entry: VaultEntry, kind: EntryKind,
                           user: String = "", password: String = "",
                           url: String = "", notes: String = "",
                           extras: [CustomField]) {
        guard let project = openProjectEntry else { return }
        let fields = extras
            .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { (label: $0.label.isEmpty ? "campo" : $0.label, value: $0.value) }

        var updated: VaultEntry
        switch kind {
        case .login, .password:
            updated = EntryMapping.credentialEntry(
                id: entry.id, kind: kind.rawValue, title: entry.title,
                user: user, password: password, url: url, notes: notes,
                extras: fields
            )
        default:
            updated = EntryMapping.detailEntry(
                id: entry.id, kind: kind.rawValue, title: entry.title, fields: fields
            )
        }
        // i campi di servizio (allegato e sua chiave) non compaiono nella
        // scheda: vanno riattaccati a mano, o modificando una voce si
        // perderebbe il documento allegato
        updated.customFields += EntryMapping.hiddenFields(of: entry)
        updated.created = entry.created
        updated.modified = Date()
        library.update(updated, in: project)
    }

    private func deleteSelectedEntry() {
        guard let project = openProjectEntry, let entry = selectedEntry else { return }
        library.delete(id: entry.id, from: project)
        selectedFolder = nil
    }

    /// La voce attualmente estratta al centro.
    private var selectedEntry: VaultEntry? {
        guard let folder = selectedFolder, folder >= 1 else { return nil }
        let list = openEntryList
        return folder - 1 < list.count ? list[folder - 1] : nil
    }

    /// Le voci ora vivono nei file .kdbx, non più in memoria: l'archivio le
    /// apre quando servono e le riscrive da sé dopo un attimo di quiete.
    @ObservedObject private var library = VaultLibrary.shared

    /// Voci vere del progetto aperto.
    private var openEntryList: [VaultEntry] {
        openProjectEntry.map { library.entries(of: $0) } ?? []
    }

    private func kind(of entry: VaultEntry) -> EntryKind {
        EntryKind(rawValue: EntryMapping.kind(of: entry)) ?? .login
    }

    /// Titoli del cassetto aperto.
    private var openEntries: [String] { openEntryList.map(\.title) }

    /// Voci per ogni cella della parete, nello stesso ordine di `cellLabels`.
    private var cellEntries: [[String]] {
        let assignments = projectAtCell
        return (0..<(cols * rows)).map { i in
            guard let p = assignments[i] else { return [] }
            // Mai decifrare qui dentro: questo codice gira mentre SwiftUI
            // disegna, e Argon2id costa mezzo secondo — la finestra si
            // pianterebbe. Se il vault del cassetto aperto non è ancora in
            // memoria se ne chiede il caricamento, che arriva per conto suo.
            guard library.isLoaded(p) else {
                if i == openCell { library.requestLoad(p) }
                return []
            }
            return library.entries(of: p).map(\.title)
        }
    }

    // NB: labels/icone/colori riflettono SOLO lo stato salvato: la bozza in
    // corso passa da draftLabel/draftIcon/draftNoteColor e viene applicata
    // in place dalla scena. Così la firma resta stabile durante la creazione
    // e non parte nessun rebuild a metà animazione.

    /// Etichette per ogni cella della parete.
    private var cellLabels: [String?] {
        let assignments = projectAtCell
        return (0..<(cols * rows)).map { assignments[$0]?.name }
    }

    private var cellIcons: [String?] {
        let assignments = projectAtCell
        return (0..<(cols * rows)).map { assignments[$0]?.icon }
    }

    private var cellNoteColors: [String?] {
        let assignments = projectAtCell
        return (0..<(cols * rows)).map { assignments[$0]?.noteColor }
    }

    /// Colori disponibili per il post-it.
    static let noteColors = ["#FADA5C", "#F4A9A8", "#A8D8B9", "#9EC5E8", "#D9B8E8", "#F0C9A0"]

    /// Stessa angolazione "storta da post-it" del foglietto in 3D (vedi
    /// `makeNote`/`updateDraft` in DrawerWall3D): stesso seed testuale →
    /// stesso hash nello stesso processo → identico angolo, così il
    /// rettangolo/icona overlay ruota insieme al post-it sotto.
    private var draftNoteAngle: Angle {
        let seed = Double(abs(createName.hashValue % 1000)) / 1000.0
        return .radians(-Double(seed * 0.18 - 0.09))
    }

    var body: some View {
        ZStack {
            DrawerWall3D(
                cols: cols,
                rows: rows,
                visibleCols: visibleCols,
                visibleRows: visibleRows,
                centerIndex: centerIndex,
                labels: cellLabels,
                icons: cellIcons,
                noteColors: cellNoteColors,
                entriesByCell: cellEntries,
                openCell: $openCell,
                selectedFolder: $selectedFolder,
                revealFolder: $revealFolder,
                folderBodyHeight: folderBodyHeight,
                folderRect: $folderRect,
                creatingCell: $creatingCell,
                plateRect: $plateRect,
                focusNote: $focusNote,
                noteRect: $noteRect,
                draftLabel: createName,
                draftIcon: newIcon,
                draftNoteColor: newNoteColor,
                onTapNewEntry: {
                    newEntryProjectID = openProjectEntry?.id
                    resetNewEntryForm(closeSheet: false)
                    entryStep = .pickType
                    showEntryFlow = true
                }
            )
            .ignoresSafeArea()

            // Velatura dello stesso colore dei cassetti: stacca i comandi dal
            // disegno della parete senza coprirla davvero. Sta dove stanno i
            // comandi — in basso a cassetti chiusi, in alto quando uno è
            // aperto (lì ci sono modifica e chiudi, e in basso non serve più).
            VStack {
                // con una cartella estratta i comandi in alto non ci sono, e
                // la sfumatura resterebbe a velare la scheda per niente
                if drawerOpen && selectedFolder == nil {
                    LinearGradient(
                        colors: [Theme.paper, Theme.paper.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 130)
                    Spacer()
                } else {
                    Spacer()
                    LinearGradient(
                        colors: [Theme.paper.opacity(0), Theme.paper],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 130)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .opacity(chromeVisible ? 1 : 0)
            .animation(.easeInOut(duration: chromeAppearDuration), value: chromeVisible)
            .animation(.easeOut(duration: 0.25), value: drawerOpen)

            VStack {
                // sono i comandi del PROGETTO: con una cartella estratta
                // c'è la sua scheda a comandare, questi sparirebbero sotto
                if drawerOpen && selectedFolder == nil {
                    HStack(spacing: 10) {
                        Button("Modifica") { startEditingOpenProject() }
                            .buttonStyle(OutlineButtonStyle())
                            .frame(width: 110)
                        Button("Chiudi") { openCell = nil }
                            .buttonStyle(OutlineButtonStyle())
                            .frame(width: 110)
                    }
                    .padding(.top, 48)
                }
                Spacer()
                if !drawerOpen && creatingCell == nil {
                    let barHeight: CGFloat = 42
                    let barWidth: CGFloat = 200 + 8 + barHeight + 8 + barHeight

                    VStack(spacing: 6) {
                        if showProjectPicker {
                            projectPickerList
                                .frame(width: barWidth)
                        } else if !searchSuggestions.isEmpty {
                            suggestionsList
                                .frame(width: barWidth)
                        }

                        HStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                                TextField("Cerca…", text: $searchText)
                                    .textFieldStyle(.plain)
                                    .font(Theme.mono(13))
                                    .foregroundStyle(Theme.ink)
                                    .onSubmit { searchAndOpenEntry() }
                            }
                            .padding(.horizontal, 14)
                            .frame(width: 200, height: barHeight)
                            .background(Theme.paper)
                            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))

                            Button {
                                startCreation()
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: barHeight, height: barHeight)
                                    .background(Theme.paper)
                                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
                            }
                            .buttonStyle(.plain)
                            .help("Nuovo progetto")
                            .background(GeometryReader { g in
                                Color.clear.preference(key: TourRectKey.self, value: g.frame(in: .named("muro")))
                            })
                            .onPreferenceChange(TourRectKey.self) { creaButtonRect = $0 }

                            Button {
                                tapNewPassword()
                            } label: {
                                Image(systemName: "key")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: barHeight, height: barHeight)
                                    .background(Theme.yellow)
                                    .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
                            }
                            .buttonStyle(.plain)
                            .help("Nuova password")
                        }
                    }
                    .padding(.bottom, 22)
                }
            }
            .opacity(chromeVisible ? 1 : 0)
            .animation(.easeInOut(duration: chromeAppearDuration), value: chromeVisible)
            .animation(.easeOut(duration: 0.25), value: drawerOpen)
            // la creazione può essere annullata anche dalla scena (click fuori):
            // qualunque sia la via d'uscita, l'interfaccia della bozza
            // (colori, campo nome, zoom post-it) va sempre smontata
            .onChange(of: creatingCell) { _, cell in
                if cell == nil { endEditing() }
            }
            // cassetto cambiato: nessuna cartella estratta, altrimenti una
            // selezione rimasta appesa terrebbe nascosti modifica/chiudi
            .onChange(of: openCell) { _, _ in
                if let f = searchPendingFolder {
                    // arrivo dalla ricerca: il cassetto si sta aprendo e la
                    // cartella va selezionata DOPO, non azzerata
                    searchPendingFolder = nil
                    DispatchQueue.main.async { selectedFolder = f }
                } else if selectedFolder != nil {
                    selectedFolder = nil
                }
            }

            // agli angoli, staccati dalla barra centrale: chiudere a sinistra,
            // impostazioni a destra
            if !drawerOpen && creatingCell == nil {
                VStack {
                    Spacer()
                    HStack {
                        cornerButton("lock", help: "Richiudi Hush") { onLock() }
                        Spacer()
                        cornerButton("gearshape", help: "Impostazioni") { showSettings = true }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .opacity(chromeVisible ? 1 : 0)
            .animation(.easeInOut(duration: chromeAppearDuration), value: chromeVisible)
            }

            // creazione: campo nome sovrapposto alla targhetta del cassetto
            // (nascosto durante lo zoom sul post-it, altrimenti resterebbe
            // appiccicato sopra il foglietto)
            if creatingCell != nil, !focusNote, let rect = plateRect {
                // il testo visibile è quello 3D sulla targhetta (segue il
                // cassetto): questo campo serve solo a raccogliere i tasti,
                // quindi è ridotto a un punto — così non compaiono nemmeno
                // l'evidenziazione della selezione o il cursore di sistema
                TextField("", text: $createName)
                    .textFieldStyle(.plain)
                    .focused($plateNameFocused)
                    .onSubmit { isEditingProject ? saveEditedProject() : confirmCreationName() }
                    .onExitCommand { endEditing() }
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .position(x: rect.midX, y: rect.midY)
                    .onAppear { plateNameFocused = true }

                if !focusNote {
                    let nameEmpty = createName.trimmingCharacters(in: .whitespaces).isEmpty
                    // un solo VStack, mai due gerarchie sorelle: così il
                    // bottone in basso (annulla / crea progetto) resta
                    // sempre nello stesso punto, cambi solo cosa c'è sopra
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 12) {
                            if nameEmpty {
                                Button("Annulla") { endEditing() }
                                    .buttonStyle(OutlineButtonStyle())
                            } else {
                                Button(isEditingProject ? "Salva" : "Crea progetto") {
                                    isEditingProject ? saveEditedProject() : confirmCreationName()
                                }
                                .buttonStyle(InkButtonStyle(prominent: true))
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: TourRectKey.self, value: g.frame(in: .named("muro")))
                                })
                                .onPreferenceChange(TourRectKey.self) { creaProgettoRect = $0 }

                                if isEditingProject {
                                    Button("Elimina progetto") { showDeleteConfirm = true }
                                        .buttonStyle(OutlineButtonStyle())
                                        .foregroundStyle(Theme.danger)
                                }
                            }
                        }
                    }
                    .frame(width: 190, height: 88)
                    // larghezza fissa: legata a rect.width cambiava mentre la
                    // camera arrivava e i testi rimbalzavano su due righe
                    .position(x: rect.midX, y: rect.maxY + (isEditingProject ? 125 : 140))
                }

                // quadrato del post-it, stessa taglia del foglietto in 3D: "+"
                // se non c'è ancora un'icona, altrimenti quella scelta —
                // il tap zooma sul post-it (colori + libreria icone)
                if let note = noteRect {
                    // in creazione (non in modifica) l'icona si sceglie DOPO
                    // il titolo: prima il post-it resta spento, così l'ordine
                    // si capisce anche senza il tour ad accompagnarlo
                    let titoloVuoto = !isEditingProject
                        && createName.trimmingCharacters(in: .whitespaces).isEmpty
                    Button {
                        if newIcon == nil { newIcon = iconLibrary.randomElement() }
                        // subito a nil, non al prossimo giro: altrimenti per
                        // un frame l'interfaccia del post-it compare ancora
                        // nella posizione di prima dello zoom
                        noteRect = nil
                        focusNote = true
                    } label: {
                        ZStack {
                            // vuoto: trasparente, si vede il cassetto in 3D dietro
                            Rectangle()
                                .fill(newIcon == nil ? Color.clear : Color(hex: newNoteColor ?? ProjectsHomeView.noteColors.first!))
                            if newIcon != nil {
                                // post-it già impostato: pulsante "modifica", non l'icona scelta
                                Image(systemName: "pencil")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                            } else {
                                // icona vera (chiarissima) + "+" sopra
                                Image(systemName: "folder")
                                    .font(.system(size: 24))
                                    .foregroundStyle(Theme.inkSoft.opacity(0.25))
                                Image(systemName: "plus")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                        // stesso colore/peso dello stroke della targhetta del titolo
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(titoloVuoto)
                    .opacity(titoloVuoto ? 0.3 : 1)
                    .animation(.easeOut(duration: 0.2), value: titoloVuoto)
                    .frame(width: note.width, height: note.height)
                    .rotationEffect(draftNoteAngle)
                    .position(x: note.midX, y: note.midY)
                }
            }

            // zoom sul post-it: colori a destra, bottoni sotto il foglietto
            if focusNote, let note = noteRect {
                VStack(spacing: 6) {
                    ForEach(Self.noteColors, id: \.self) { hex in
                        Button { newNoteColor = hex } label: {
                            ZStack {
                                // selezione: anello staccato, non sul quadrato stesso
                                if newNoteColor == hex {
                                    Rectangle()
                                        .strokeBorder(Theme.ink, lineWidth: 1.5)
                                        .frame(width: 32, height: 32)
                                }
                                Rectangle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 24, height: 24)
                                    .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.4), lineWidth: 1))
                            }
                            .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .position(x: note.maxX + 44, y: note.midY)

                VStack(spacing: 10) {
                    Button(newIcon == nil ? "Scegli icona" : "Cambia icona") {
                        showIconLibrary = true
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .background(GeometryReader { g in
                        Color.clear.preference(key: TourRectKey.self, value: g.frame(in: .named("muro")))
                    })
                    .onPreferenceChange(TourRectKey.self) { iconButtonRect = $0 }

                    HStack(spacing: 10) {
                        Button("Annulla") {
                            newIcon = nil
                            focusNote = false
                        }
                        .buttonStyle(OutlineButtonStyle())

                        Button("Fatto") { focusNote = false }
                            .buttonStyle(InkButtonStyle(prominent: true))
                            .background(GeometryReader { g in
                                Color.clear.preference(key: TourRectKey.self, value: g.frame(in: .named("muro")))
                            })
                            .onPreferenceChange(TourRectKey.self) { salvaIconaRect = $0 }
                    }
                }
                .frame(width: 230)
                .position(x: note.midX, y: note.maxY + 70)
            }

            // dati sovrapposti ESATTAMENTE al corpo della cartella estratta
            // (rettangolo proiettato dalla scena 3D — sono la stessa cosa)
            if let folder = selectedFolder, let entry = selectedEntry, let rect = folderRect {
                let entryKind = kind(of: entry)

                if entryKind == .login || entryKind == .password {
                    EntryCard(
                        number: folder,
                        name: entry.title,
                        user: entry.username,
                        password: entry.password,
                        url: entry.url,
                        notes: entry.notes,
                        extras: EntryMapping.details(of: entry).map {
                            var f = CustomField(); f.label = $0.label; f.value = $0.value; return f
                        },
                        onSave: { u, p, r, n, extras in
                            saveEdits(to: entry, kind: entryKind,
                                      user: u, password: p, url: r, notes: n,
                                      extras: extras)
                        },
                        onClose: { selectedFolder = nil },
                        onDelete: { showDeleteEntryConfirm = true }
                    )
                    // margini veri dentro il corpo della cartella: prima il
                    // contenuto arrivava a filo dei bordi e sembrava stare
                    // fuori invece che dentro
                    .frame(width: rect.width * 0.82, height: rect.height * 0.78)
                    .position(x: rect.midX, y: rect.midY + rect.height * 0.04)
                    .id(folder)
                } else {
                    // tipi non-credenziale: stessi campi salvati in creazione,
                    // modificabili come quelli delle credenziali
                    GenericEntryCard(
                        number: folder,
                        name: entry.title,
                        icon: entryKind.icon,
                        rows: EntryMapping.details(of: entry).map {
                            var f = CustomField(); f.label = $0.label; f.value = $0.value; return f
                        },
                        onSave: { rows in
                            saveEdits(to: entry, kind: entryKind, extras: rows)
                        },
                        onClose: { selectedFolder = nil },
                        onDelete: { showDeleteEntryConfirm = true }
                    )
                    // margini veri dentro il corpo della cartella: prima il
                    // contenuto arrivava a filo dei bordi e sembrava stare
                    // fuori invece che dentro
                    .frame(width: rect.width * 0.82, height: rect.height * 0.78)
                    .position(x: rect.midX, y: rect.midY + rect.height * 0.04)
                    .id(folder)
                }
            }

            // parete vuota, appena entrati: tour in tre tappe, si avanza
            // toccando i bersagli veri, si spegne da solo per sempre.
            // Stessa dissolvenza di tutto il resto della chrome alla PRIMA
            // apparizione (non uno scatto secco appena la porta si apre);
            // i cambi di tappa dopo hanno la loro, più veloce.
            // sempre nell'albero (mai un `if` che la fa sparire di scatto):
            // così l'ultima tappa si dissolve invece di sparire secca
            // quando tourStep passa a .done
            tourOverlay
                .opacity(tourVisible ? (chromeVisible ? 1 : 0) : 0)
                // parte solo quando il resto della chrome ha già finito
                // la sua dissolvenza (1.6s), non insieme
                .animation(.easeInOut(duration: 0.25).delay(chromeVisible && tourVisible ? chromeAppearDuration : 0), value: chromeVisible)
                .animation(.easeInOut(duration: 0.35), value: tourVisible)
                .allowsHitTesting(tourVisible)

            // sempre in basso a sinistra: chi non vuole seguire il tour se
            // ne libera in un tap, in ogni tappa
            VStack {
                Spacer()
                HStack {
                    Button("Salta") {
                        tourStep = .done
                        Preferences.vistoAiutoParete = true
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .fixedSize()
                    Spacer()
                }
            }
            .padding(22)
            .opacity(tourVisible ? (chromeVisible ? 1 : 0) : 0)
            .animation(.easeInOut(duration: 0.25).delay(chromeVisible && tourVisible ? chromeAppearDuration : 0), value: chromeVisible)
            .animation(.easeInOut(duration: 0.35), value: tourVisible)
            .allowsHitTesting(tourVisible)
        }
        .coordinateSpace(name: "muro")
        // stesso sistema di coordinate della SCNView (che ignora il safe area):
        // senza, il rect proiettato della cartella risulta spostato in basso
        .ignoresSafeArea()
        .paperBackground()
        .preferredColorScheme(.light)
        .sheet(isPresented: $showOpenPasswordSheet) {
            openPasswordSheet.sheetPaper()
        }
        .sheet(isPresented: $showEntryFlow, onDismiss: { entryStep = .pickType }) {
            // misura FISSA per tutti i passi: cambiando taglia fra categoria
            // e modulo la finestra della sheet si ridimensionava e per un
            // frame mostrava il vuoto — è quello il lampo nero
            ZStack {
                // fondo che riempie TUTTA la finestra della sheet: messo solo
                // dietro al contenuto restava scoperta la cornice, ed è lì
                // che si vedeva il nero durante la presentazione
                Theme.paper.ignoresSafeArea()
                switch entryStep {
                case .pickType: entryTypePicker
                case .form: newEntrySheet
                }
            }
            .frame(width: 420, height: 560)
            .preferredColorScheme(.light)
        }
        // Chiuse le impostazioni si rilegge l'elenco: da lì dentro si possono
        // importare cassetti nuovi, e senza questo la parete restava com'era
        // finché non si riapriva Hush.
        .sheet(isPresented: $showSettings, onDismiss: {
            projects = VaultFileManager.shared.projects
            Task { await library.preload(projects) }
        }) {
            SettingsView(onClose: { showSettings = false },
                         onImport: { consumePendingImport() })
                .sheetPaper()
        }
        .sheet(isPresented: $showIconLibrary) {
            IconLibrarySheet(selected: newIcon, search: $iconSearch, library: iconLibrary) { picked in
                newIcon = (newIcon == picked ? nil : picked)
                showIconLibrary = false
                // qui, non al dismiss della sheet: è il momento esatto in
                // cui l'icona è stata davvero scelta
                if tourStep == .scegliIconaLib { tourStep = .scegliColore }
            }
            .sheetPaper()
        }
        .alert("Errore", isPresented: .constant(localError != nil), actions: {
            Button("OK") { localError = nil }
        }, message: { Text(localError ?? "") })
        .alert("Eliminare il progetto?", isPresented: $showDeleteConfirm, actions: {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) { deleteEditedProject() }
        }, message: { Text("Il cassetto e tutto quello che contiene vengono cancellati. Non si può annullare.") })
        .alert("Eliminare questa voce?", isPresented: $showDeleteEntryConfirm, actions: {
            Button("Annulla", role: .cancel) {}
            Button("Elimina", role: .destructive) { deleteSelectedEntry() }
        }, message: { Text("Non si può annullare.") })
        .onChange(of: showSettingsSignal?.wrappedValue ?? false) { _, wants in
            if wants { showSettings = true; showSettingsSignal?.wrappedValue = false }
        }
        // il tour avanza da solo seguendo quello che l'utente fa davvero,
        // non un bottone "avanti" a parte
        .onChange(of: creatingCell) { _, cell in
            if tourStep == .creaCassetto, cell != nil { tourStep = .scriviTitolo }
            // creazione annullata prima di finire: si torna al "+", o il
            // tour resterebbe appeso a una targhetta o un post-it che non
            // ci sono più
            let inCreazione: Set<TourStep> = [.scriviTitolo, .tapPostIt, .scegliIconaLib, .scegliColore, .premiSalva, .creaProgetto]
            if inCreazione.contains(tourStep), cell == nil, !showEntryFlow {
                tourStep = .creaCassetto
            }
        }
        .onChange(of: focusNote) { _, zoomato in
            // lo zoom sul post-it è finito: si passa dal "toccalo" a
            // "scegli l'icona", stesso rettangolo, tappa diversa
            if tourStep == .tapPostIt, zoomato { tourStep = .scegliIconaLib }
            // "Fatto" sul post-it: si torna alla targhetta, tocca al
            // bottone Crea progetto
            if tourStep == .premiSalva, !zoomato { tourStep = .creaProgetto }
        }
        .onChange(of: showIconLibrary) { _, aperta in
            // libreria icone chiusa (scelta o no): tocca al colore adesso
            if tourStep == .scegliIconaLib, !aperta { tourStep = .scegliColore }
        }
        .onChange(of: newNoteColor) { _, _ in
            if tourStep == .scegliColore { tourStep = .premiSalva }
        }
        .onChange(of: tourStep) { _, nuovo in
            // resta sull'ultima tappa vera finché la dissolvenza non ha
            // finito: EmptyView() subito farebbe sparire tutto di scatto
            if nuovo != .done { tourDisplayStep = nuovo }
        }
        .onAppear {
            projects = VaultFileManager.shared.projects
            if !projects.isEmpty { tourStep = .done }
            consumePendingImport()
            // i vault si aprono in anticipo, in sottofondo: così cliccando un
            // cassetto le cartelle ci sono già invece di comparire dopo
            Task { await library.preload(projects) }
        }
    }

    /// Le voci scelte in onboarding finiscono in un cassetto loro. Va fatto
    /// qui e non nell'onboarding: là il vault non esiste ancora, nasce con la
    /// master password appena scelta.
    private func consumePendingImport() {
        guard !PendingImport.isEmpty, let key = MasterKey.session else { return }
        let name = PendingImport.projectName
        let imported = PendingImport.entries
        PendingImport.clear()

        vm.createNew(name: name, password: key)
        Task { @MainActor in
            guard let bytes = await vm.save() else { return }
            do {
                let url = VaultFileManager.shared.freeProjectURL(named: name)
                try Data(bytes).write(to: url, options: .atomic)
                try VaultFileManager.shared.addProject(name: name, url: url,
                                                       icon: "square.and.arrow.down",
                                                       noteColor: Self.noteColors.first)
                projects = VaultFileManager.shared.projects
                guard let created = projects.first(where: { $0.path == url.path }) else { return }

                // nomi doppi nello stesso cassetto renderebbero ambigue le
                // schede, che si cercano per titolo
                var used = Set<String>()
                for imp in imported {
                    var title = imp.title
                    var n = 2
                    while used.contains(title) { title = "\(imp.title) (\(n))"; n += 1 }
                    used.insert(title)
                    library.add(
                        EntryMapping.credentialEntry(
                            kind: EntryKind.login.rawValue, title: title,
                            user: imp.username, password: imp.password,
                            url: imp.url, notes: imp.notes, extras: []
                        ),
                        to: created
                    )
                }
                // le voci importate valgono la scrittura subito: sono tante e
                // averle solo in memoria fino al prossimo respiro è un rischio
                library.flush(created)
            } catch {
                localError = "Import non riuscito: \(error.localizedDescription)"
            }
        }
    }

    /// Voci che matchano la ricerca corrente, in TUTTI i progetti: (progetto,
    /// indice nel suo cassetto, nome voce).
    private var searchSuggestions: [(project: VaultFileManager.Project, folder: Int, name: String)] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        // solo fra i vault già aperti: cercare ovunque vorrebbe dire
        // decifrare ogni progetto a ogni lettera digitata
        return projects.filter { library.isLoaded($0) }.flatMap { p -> [(project: VaultFileManager.Project, folder: Int, name: String)] in
            library.entries(of: p).map(\.title).enumerated()
                .filter { $0.element.lowercased().contains(q) }
                .map { (project: p, folder: $0.offset + 1, name: $0.element) }
        }
        .prefix(6)
        .map { $0 }
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(searchSuggestions.enumerated()), id: \.offset) { i, s in
                Button {
                    searchText = ""
                    openEntry(project: s.project, folder: s.folder)
                } label: {
                    HStack {
                        Text(s.name.lowercased())
                            .font(Theme.mono(12, .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(s.project.name.lowercased())
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if i != searchSuggestions.count - 1 {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
        }
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
    }

    /// Apre il cassetto del progetto scelto (se non è già quello aperto) e
    /// estrae la cartella al centro.
    private func openEntry(project: VaultFileManager.Project, folder: Int) {
        let cell = cellIndex(for: project)
        if openCell != cell {
            searchPendingFolder = folder
            openCell = cell
        } else {
            selectedFolder = folder
        }
    }

    private static let entryTypeOrder: [EntryKind] = [.login, .secureNote, .card, .identity, .password, .document]

    private var entryTypePicker: some View {
        // stessa testata del modulo che segue: prima aveva 40 pt di margine
        // in più in cima e i due passi partivano ad altezze diverse
        VStack(alignment: .leading, spacing: 16) {
            IndexLabel(text: "Cosa vuoi creare")
                .padding(.bottom, 6)

            ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                ForEach(Self.entryTypeOrder, id: \.self) { kind in
                    Button {
                        newEntryKind = kind
                        resetNewEntryForm(closeSheet: false)
                        entryStep = .form
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 20))
                            Text(kind.label)
                                .font(Theme.mono(11, .semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                // va a capo invece di stringersi fino a
                                // toccare i bordi (es. "carta di credito")
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 8)
                        }
                        .foregroundStyle(Theme.ink)
                        // stessa dimensione per tutti, testo corto o lungo che sia
                        .frame(maxWidth: .infinity)
                        .frame(height: 92)
                        .background(Theme.paperRaised)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            }

            Spacer(minLength: 0)

            Button("Annulla") {
                showEntryFlow = false
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var newEntrySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            IndexLabel(number: (currentNewEntryProject.map { library.entries(of: $0).count } ?? 0) + 1, text: "nuovo · \(newEntryKind.label)")
                .padding(.bottom, 6)

            GeometryReader { outer in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GeometryReader { g in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("scrollNewEntry")).minY)
                    }
                    .frame(height: 0)
                    // progetto: scelto prima di entrare qui, ma cambiabile
                    // senza uscire. Menu a tendina di sistema, come quelli
                    // delle impostazioni: prima era un finto menu disegnato
                    // a mano e stonava col resto.
                    // Tendina fatta in casa, non un Menu di sistema: quello si
                    // porta dietro il proprio sfondo e la propria lista, che
                    // non c'entrano niente con la carta del resto. Qui il
                    // campo è identico agli altri e l'elenco è lo stesso
                    // riquadro dei suggerimenti della ricerca.
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Progetto")

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showEntryProjectList.toggle()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text((currentNewEntryProject?.name ?? "progetto").lowercased())
                                    .font(Theme.mono(13))
                                    .foregroundStyle(Theme.ink)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.inkSoft)
                                    .rotationEffect(.degrees(showEntryProjectList ? 180 : 0))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.paperRaised)
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(projects.count <= 1)

                        if showEntryProjectList {
                            // bassa e scrollabile: con molti progetti l'elenco
                            // aperto spingeva fuori dal modulo tutto il resto
                            ScrollView {
                            VStack(spacing: 0) {
                                ForEach(Array(projects.enumerated()), id: \.element.id) { i, p in
                                    Button {
                                        newEntryProjectID = p.id
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            showEntryProjectList = false
                                        }
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: p.icon ?? "folder")
                                                .font(.system(size: 12))
                                                .frame(width: 16)
                                            Text(p.name.lowercased())
                                                .font(Theme.mono(12, .semibold))
                                            Spacer(minLength: 0)
                                            if p.id == currentNewEntryProject?.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .semibold))
                                            }
                                        }
                                        .foregroundStyle(Theme.ink)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 9)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)

                                    if i != projects.count - 1 {
                                        Rectangle().fill(Theme.line).frame(height: 1)
                                    }
                                }
                            }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                            .frame(maxHeight: 132)
                            .background(Theme.paper)
                            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
                        }
                    }

                    // Il titolo è il nome della CARTELLA, non un campo come
                    // gli altri: sta in cima, staccato, con la sua etichetta.
                    VStack(alignment: .leading, spacing: 6) {
                        fieldLabel("Nome della cartella")
                        AutoFocusField(placeholder: "Titolo", text: $newEntryName)
                    }

                    Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)
                        .padding(.vertical, 2)

                    fieldLabel("Cosa c'è dentro")

                    switch newEntryKind {
                    case .login, .password:
                        loginFields
                    case .secureNote:
                        secureNoteFields
                    case .document:
                        documentFields
                    case .card:
                        cardFields
                    case .identity:
                        identityFields
                    }

                    if newEntryKind != .secureNote {
                        TextField("Note", text: $newEntryNotes, axis: .vertical)
                            .textFieldStyle(PaperFieldStyle())
                            .lineLimit(1...5)
                    }

                    GeometryReader { g in
                        Color.clear.preference(key: ScrollBottomKey.self, value: g.frame(in: .named("scrollNewEntry")).maxY)
                    }
                    .frame(height: 0)
                }
                .padding(.trailing, 4)   // spazio per la scrollbar
            }
            .coordinateSpace(name: "scrollNewEntry")
            .onPreferenceChange(ScrollOffsetKey.self) { y in newEntryScrolled = y < -4 }
            .onPreferenceChange(ScrollBottomKey.self) { y in newEntryAtBottom = y <= outer.size.height + 4 }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)
            .scrollFade(top: newEntryScrolled, bottom: !newEntryAtBottom)
            }

            if !newEntryName.trimmingCharacters(in: .whitespaces).isEmpty && !newEntryHasContent {
                Text("Serve almeno un dato oltre al titolo")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
            }

            HStack(spacing: 10) {
                Button("Annulla") { resetNewEntryForm() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(width: 120)
                Button("Crea") { confirmNewEntry() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .disabled(!canCreateNewEntry)
                    .opacity(canCreateNewEntry ? 1 : 0.4)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(isPresented: $showDocumentImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { pendingDocumentURL = url }
        }
    }

    @ViewBuilder private var loginFields: some View {
        TextField("Utente / email", text: $newEntryUser)
            .textFieldStyle(PaperFieldStyle())

        HStack(spacing: 8) {
            Group {
                if revealNewEntryPassword {
                    TextField("Password", text: $newEntryPassword)
                } else {
                    SecureField("Password", text: $newEntryPassword)
                }
            }
            .textFieldStyle(.plain)
            .font(Theme.mono(13))
            .focused($newEntryPasswordFocused)

            Button { revealNewEntryPassword.toggle() } label: {
                Image(systemName: revealNewEntryPassword ? "eye.slash" : "eye")
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)

            Button { newEntryPassword = Self.randomPassword() } label: {
                Image(systemName: "die.face.5")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .foregroundStyle(newEntryPasswordFocused ? Theme.ink : Theme.inkSoft)
            .padding(4)
            .background(newEntryPasswordFocused ? Theme.yellow.opacity(0.7) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .help("genera una password casuale")
            .overlay(alignment: .top) {
                if newEntryPasswordFocused {
                    Text("Random")
                        .font(Theme.mono(9, .semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.ink)
                        .fixedSize()
                        .offset(y: -22)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: newEntryPasswordFocused)
        .frame(height: Theme.fieldHeight)
        .padding(.horizontal, 10)
        .background(Theme.paperRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

        // url: più di uno, come i "siti web" di 1Password
        VStack(alignment: .leading, spacing: 8) {
            ForEach($newEntryURLs) { $url in
                HStack(spacing: 8) {
                    TextField("Url", text: $url.value)
                        .textFieldStyle(PaperFieldStyle())
                    if newEntryURLs.count > 1 {
                        Button {
                            newEntryURLs.removeAll { $0.id == url.id }
                        } label: {
                            Image(systemName: "minus.circle").foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button { newEntryURLs.append(IdentifiedString()) } label: {
                Label("Aggiungi un altro url", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.inkSoft)
        }

        // campi extra: come i "campi personalizzati" di 1Password —
        // testo libero o mascherato come una password
        VStack(alignment: .leading, spacing: 8) {
            ForEach($newEntryFields) { $field in
                HStack(spacing: 8) {
                    TextField("Etichetta", text: $field.label)
                        .textFieldStyle(PaperFieldStyle())
                        .frame(width: 110)
                    Group {
                        if field.isSecret {
                            SecureField("Valore", text: $field.value)
                        } else {
                            TextField("Valore", text: $field.value)
                        }
                    }
                    .textFieldStyle(PaperFieldStyle())
                    Button { field.isSecret.toggle() } label: {
                        Image(systemName: field.isSecret ? "lock.fill" : "lock.open")
                            .foregroundStyle(Theme.inkSoft)
                    }
                    .buttonStyle(.plain)
                    Button {
                        newEntryFields.removeAll { $0.id == field.id }
                    } label: {
                        Image(systemName: "minus.circle").foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { newEntryFields.append(CustomField()) } label: {
                Label("Aggiungi un campo", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder private var cardFields: some View {
        TextField("Intestatario", text: $newCardHolder)
            .textFieldStyle(PaperFieldStyle())
        TextField("Numero carta", text: $newCardNumber)
            .textFieldStyle(PaperFieldStyle())
        HStack(spacing: 8) {
            TextField("Scadenza (MM/AA)", text: $newCardExpiry)
                .textFieldStyle(PaperFieldStyle())
                // la barra la mette lui dopo il mese: si scrivono solo i numeri
                .onChange(of: newCardExpiry) { _, v in
                    let formatted = Self.formatExpiry(v)
                    if formatted != v { newCardExpiry = formatted }
                }
            TextField("Cvv", text: $newCardCVV)
                .textFieldStyle(PaperFieldStyle())
                .frame(width: 90)
                // solo cifre, al massimo quattro: tre sulla gran parte dei
                // circuiti, quattro su American Express
                .onChange(of: newCardCVV) { _, v in
                    let digits = String(v.filter(\.isNumber).prefix(4))
                    if digits != v { newCardCVV = digits }
                }
        }
        TextField("Pin", text: $newCardPIN)
            .textFieldStyle(PaperFieldStyle())
    }

    @ViewBuilder private var identityFields: some View {
        HStack(spacing: 8) {
            TextField("Nome", text: $newIdentityFirstName)
                .textFieldStyle(PaperFieldStyle())
            TextField("Cognome", text: $newIdentityLastName)
                .textFieldStyle(PaperFieldStyle())
        }
        TextField("Indirizzo", text: $newIdentityAddress)
            .textFieldStyle(PaperFieldStyle())
        TextField("Telefono", text: $newIdentityPhone)
            .textFieldStyle(PaperFieldStyle())
        TextField("Email", text: $newIdentityEmail)
            .textFieldStyle(PaperFieldStyle())
    }

    /// File leggero allegato: copiato negli allegati dell'app alla creazione,
    /// così resta raggiungibile anche se l'originale sparisce.
    @ViewBuilder private var secureNoteFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array($newSecureNotes.enumerated()), id: \.element.id) { i, $note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Titolo della nota \(i + 1)", text: $note.label)
                            .textFieldStyle(PaperFieldStyle())
                        if newSecureNotes.count > 1 {
                            Button {
                                newSecureNotes.removeAll { $0.id == note.id }
                            } label: {
                                Image(systemName: "minus.circle").foregroundStyle(Theme.danger)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Testo", text: $note.value, axis: .vertical)
                        .textFieldStyle(PaperFieldStyle())
                        .lineLimit(1...6)
                }
            }
            Button { newSecureNotes.append(CustomField()) } label: {
                Label("Aggiungi un'altra nota", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder private var documentFields: some View {
        if let url = pendingDocumentURL {
            HStack(spacing: 8) {
                Image(systemName: "doc").foregroundStyle(Theme.inkSoft)
                Text(url.lastPathComponent)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button { pendingDocumentURL = nil } label: {
                    Image(systemName: "minus.circle").foregroundStyle(Theme.danger)
                }
                .buttonStyle(.plain)
            }
            .themedRow()
        } else {
            Button { showDocumentImporter = true } label: {
                Label("Scegli file…", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(OutlineButtonStyle())
        }
    }

    private var currentNewEntryProject: VaultFileManager.Project? {
        projects.first { $0.id == newEntryProjectID } ?? projects.first
    }

    /// Almeno un dato oltre al titolo: una cartella col solo nome non
    /// contiene niente e non ci si può fare nulla dopo.
    private var newEntryHasContent: Bool {
        func filled(_ s: String) -> Bool { !s.trimmingCharacters(in: .whitespaces).isEmpty }
        switch newEntryKind {
        case .login, .password:
            return filled(newEntryUser) || filled(newEntryPassword)
                || newEntryURLs.contains { filled($0.value) }
                || newEntryFields.contains { filled($0.value) }
                || filled(newEntryNotes)
        case .secureNote:
            return newSecureNotes.contains { filled($0.value) }
        case .card:
            return filled(newCardHolder) || filled(newCardNumber) || filled(newCardExpiry)
                || filled(newCardCVV) || filled(newCardPIN) || filled(newEntryNotes)
        case .identity:
            return filled(newIdentityFirstName) || filled(newIdentityLastName)
                || filled(newIdentityAddress) || filled(newIdentityPhone)
                || filled(newIdentityEmail) || filled(newEntryNotes)
        case .document:
            return pendingDocumentURL != nil || filled(newEntryNotes)
        }
    }

    private var canCreateNewEntry: Bool {
        !newEntryName.trimmingCharacters(in: .whitespaces).isEmpty && newEntryHasContent
    }

    /// "1225" → "12/25". Tiene solo le cifre e taglia a quattro, così
    /// incollare una data già formattata non raddoppia la barra.
    ///
    /// A due cifre la barra NON c'è: altrimenti cancellando all'indietro
    /// ricomparirebbe subito e il campo sembrerebbe bloccato.
    static func formatExpiry(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        guard digits.count > 2 else { return digits }
        return "\(digits.prefix(2))/\(digits.dropFirst(2))"
    }

    private static func randomPassword() -> String {
        var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        if Preferences.passwordSymbols { chars += "!?#%&*+-=@" }
        return String((0..<Preferences.passwordLength).compactMap { _ in chars.randomElement() })
    }

    private func resetNewEntryForm(closeSheet: Bool = true) {
        if closeSheet { showEntryFlow = false }
        showEntryProjectList = false
        newEntryName = ""; newEntryUser = ""; newEntryPassword = ""
        newEntryURLs = [IdentifiedString()]; newEntryFields = []; newEntryNotes = ""
        newSecureNotes = [CustomField()]
        revealNewEntryPassword = false
        newCardHolder = ""; newCardNumber = ""; newCardExpiry = ""; newCardCVV = ""; newCardPIN = ""
        newIdentityFirstName = ""; newIdentityLastName = ""; newIdentityAddress = ""
        newIdentityPhone = ""; newIdentityEmail = ""
        pendingDocumentURL = nil
    }

    /// Costruisce la voce e la mette nel vault del progetto. I campi cambiano
    /// col tipo: accesso e password usano i campi canonici del KDBX, gli altri
    /// i campi liberi, che il formato prevede.
    private func confirmNewEntry() {
        let name = newEntryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty,
              let projectID = newEntryProjectID,
              let project = projects.first(where: { $0.id == projectID }) else { return }

        let entry: VaultEntry
        switch newEntryKind {
        case .login, .password:
            // url in più e campi personalizzati: vanno conservati, o in
            // modifica sparirebbero pezzi di quel che avevi inserito
            var extras: [(label: String, value: String)] = []
            extras += newEntryURLs.dropFirst()
                .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ("url", $0.value) }
            extras += newEntryFields
                .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.label.isEmpty ? "campo" : $0.label, $0.value) }
            entry = EntryMapping.credentialEntry(
                kind: newEntryKind.rawValue, title: name,
                user: newEntryUser,
                password: newEntryPassword,
                url: newEntryURLs.first?.value ?? "",
                notes: newEntryNotes,
                extras: extras
            )

        case .secureNote:
            let notes = newSecureNotes.enumerated()
                .filter { !$0.element.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { i, note -> (label: String, value: String) in
                    let title = note.label.trimmingCharacters(in: .whitespaces)
                    return (title.isEmpty ? "nota \(i + 1)" : title, note.value)
                }
            entry = EntryMapping.detailEntry(kind: newEntryKind.rawValue, title: name, fields: notes)

        case .card:
            entry = EntryMapping.detailEntry(kind: newEntryKind.rawValue, title: name, fields: [
                ("intestatario", newCardHolder), ("numero carta", newCardNumber),
                ("scadenza", newCardExpiry), ("cvv", newCardCVV),
                ("pin", newCardPIN), ("note", newEntryNotes)
            ].filter { !$0.1.isEmpty })

        case .identity:
            entry = EntryMapping.detailEntry(kind: newEntryKind.rawValue, title: name, fields: [
                ("nome", newIdentityFirstName), ("cognome", newIdentityLastName),
                ("indirizzo", newIdentityAddress), ("telefono", newIdentityPhone),
                ("email", newIdentityEmail), ("note", newEntryNotes)
            ].filter { !$0.1.isEmpty })

        case .document:
            var fields = [("note", newEntryNotes)].filter { !$0.1.isEmpty }
            if let src = pendingDocumentURL {
                do {
                    // il file viene cifrato e messo negli allegati dell'app:
                    // nel vault finiscono percorso e chiave, così il documento
                    // è protetto quanto le password e resta raggiungibile
                    // anche se l'originale viene spostato
                    let saved = try AttachmentVault.store(src)
                    fields.insert(("file", src.lastPathComponent), at: 0)
                    fields.append(("scrigno.allegato", saved.path))
                    fields.append(("scrigno.allegato.chiave", saved.key))
                } catch {
                    localError = "Impossibile allegare il file: \(error.localizedDescription)"
                }
            }
            entry = EntryMapping.detailEntry(kind: newEntryKind.rawValue, title: name, fields: fields)
        }

        resetNewEntryForm()   // chiude il modulo

        // La voce in più fa ricostruire la scena 3D (una cartella nuova nel
        // cassetto): farlo mentre la sheet si sta chiudendo dava un lampo
        // nero. Prima si chiude, poi si tocca la scena.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            library.add(entry, to: project)
            // appena creata si alza nel nastro, come arrivandoci scrollando
            let cell = cellIndex(for: project)
            if openCell != cell { openCell = cell }
            revealFolder = library.entries(of: project).count
        }
    }

    /// "+ nuova password": scegli sempre prima IL PROGETTO (con uno solo si
    /// salta direttamente), poi il modulo. Non tocca il cassetto.
    private func tapNewPassword() {
        if showProjectPicker { showProjectPicker = false; return }
        if projects.count > 1 {
            showProjectPicker = true
        } else if let only = projects.first {
            newEntryProjectID = only.id
            entryStep = .pickType
            showEntryFlow = true
        }
    }

    private var projectPickerList: some View {
        ScrollView {
        VStack(spacing: 0) {
            ForEach(projects) { p in
                Button {
                    showProjectPicker = false
                    newEntryProjectID = p.id
                    entryStep = .pickType
                    showEntryFlow = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.icon ?? "folder")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 18)
                        Text(p.name.lowercased())
                            .font(Theme.mono(12, .semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if p.id != projects.last?.id {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
            }
        }
        }
        .frame(maxHeight: 280)
        .background(Theme.paper)
        .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
    }

    // MARK: - Creazione: avvicinati al primo cassetto libero e scrivi il nome

    /// Prima cella libera nell'ordine a spirale (centro → esterno).
    private var nextFreeCell: Int? {
        let order = spiralOrder
        return projects.count < order.count ? order[projects.count] : nil
    }

    /// Sotto al post-it: il post-it sta a destra sul fronte del cassetto,
    /// quindi i controlli si allineano lì e non al centro della targhetta.
    private func postItAnchorX(_ rect: CGRect) -> CGFloat {
        rect.midX + rect.width * 0.62
    }

    /// "modifica" sul cassetto aperto: torna alla vista targhetta, con nome,
    /// icona e colore già compilati, per ritoccarli.
    private func startEditingOpenProject() {
        guard let cell = openCell, let p = projectAtCell[cell] else { return }
        editingProjectID = p.id
        isEditingProject = true
        createName = p.name
        newIcon = p.icon
        newNoteColor = p.noteColor ?? ProjectsHomeView.noteColors.first
        // prima la modalità modifica, poi la chiusura: così closeDrawer sa
        // che deve lasciare la camera a enterCreation (un unico movimento)
        creatingCell = cell
        openCell = nil
    }

    private func saveEditedProject() {
        let name = createName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let id = editingProjectID else { return }
        VaultFileManager.shared.updateProject(id: id, name: name, icon: newIcon, noteColor: newNoteColor)
        endEditing()
        // dopo l'animazione di uscita, non nello stesso istante: altrimenti
        // il rebuild della scena (nome cambiato) e lo zoom-out di ritorno
        // partono insieme e il movimento non è fluido come gli altri
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            projects = VaultFileManager.shared.projects
        }
    }

    private func deleteEditedProject() {
        guard let id = editingProjectID else { return }
        VaultFileManager.shared.deleteProject(id: id)
        projects = VaultFileManager.shared.projects
        openCell = nil
        selectedFolder = nil
        endEditing()
    }

    private func endEditing() {
        isEditingProject = false
        editingProjectID = nil
        focusNote = false
        noteRect = nil
        creatingCell = nil
        createName = ""
        newIcon = nil
        newNoteColor = ProjectsHomeView.noteColors.first
    }

    /// Tre tappe, una alla volta: si avanza toccando il bersaglio vero (il
    /// + , poi il post-it), non un bottone "avanti" separato — così chi
    /// segue il fumetto sta anche davvero facendo la cosa. Si chiude una
    /// volta sola per sempre (Preferences.vistoAiutoParete).
    private enum TourStep {
        case creaCassetto, scriviTitolo, tapPostIt, scegliIconaLib, scegliColore, premiSalva, creaProgetto, done
    }

    /// Rettangolo del "+", per bucare la velatura esattamente lì sopra.
    private struct TourRectKey: PreferenceKey {
        static var defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
    }

    /// Vera finché il tour non è chiuso per sempre: guida sia l'opacità
    /// (fade, non scatto) sia l'hit-testing del velo.
    private var tourVisible: Bool { tourStep != .done }

    @ViewBuilder
    private var tourOverlay: some View {
        // resta sull'ultima tappa vera anche a tourStep == .done: così la
        // dissolvenza mostra ancora il contenuto mentre sparisce, invece
        // di lasciare vuoto da subito
        switch tourStep == .done ? tourDisplayStep : tourStep {
        case .creaCassetto:
            if creaButtonRect != .zero {
                spotlight(creaButtonRect, testo: "Premi qui per creare il primo progetto.")
            }
        case .scriviTitolo:
            if let targhetta = plateRect {
                let nomeScritto = !createName.trimmingCharacters(in: .whitespaces).isEmpty
                spotlight(targhetta, testo: "Scrivi un titolo per il cassetto.",
                          ctaLabel: nomeScritto ? "Fatto" : nil,
                          cta: nomeScritto ? { tourStep = .tapPostIt } : nil)
            }
        case .tapPostIt:
            // il post-it stesso resta il bersaglio anche mentre la scena
            // fa lo zoom: è lo stesso rettangolo (noteRect), la camera lo
            // muove ma non lo fa mai sparire — niente buco che sfarfalla
            if let nota = noteRect {
                spotlight(nota, testo: "Tocca il post-it per dargli un'icona e un colore.", angolo: draftNoteAngle)
            }
        case .scegliIconaLib:
            // durante lo zoom della camera noteRect è nil e i bottoni non
            // sono ancora a schermo: velo pieno senza buco, così l'overlay
            // resta lì invece di sparire e riapparire (il glitch)
            if focusNote, let nota = noteRect, iconButtonRect != .zero {
                spotlight(iconButtonRect, testo: "Scegli un'icona per il cassetto.", anche: nota, ancheAngolo: draftNoteAngle)
            } else {
                velo("Scegli un'icona per il cassetto.")
            }
        case .scegliColore:
            // niente GeometryReader qui: la colonna sta in un punto noto
            // rispetto al post-it (maxX + 44, centrata in verticale), il
            // rettangolo si calcola e basta — misurarla via preference si
            // era rivelato inaffidabile con la sheet delle icone di mezzo
            if let nota = noteRect {
                let n = CGFloat(Self.noteColors.count)
                let altezza = n * 32 + (n - 1) * 6
                let rect = CGRect(x: nota.maxX + 44 - 16, y: nota.midY - altezza / 2,
                                  width: 32, height: altezza)
                spotlight(rect, testo: "Ora un colore per il post-it.", anche: nota, ancheAngolo: draftNoteAngle)
            }
        case .premiSalva:
            if focusNote, let nota = noteRect, salvaIconaRect != .zero {
                spotlight(salvaIconaRect, testo: "Premi Fatto per confermare.", anche: nota, ancheAngolo: draftNoteAngle)
            } else {
                velo("Premi Fatto per confermare.")
            }
        case .creaProgetto:
            // misurato sul bottone vero, non derivato dalla targhetta: così
            // il buco lo segue anche mentre la camera torna dall'icona
            if !focusNote, creaProgettoRect != .zero {
                spotlight(creaProgettoRect, testo: "Premi Crea progetto: il cassetto è pronto.")
            } else {
                velo("Premi Crea progetto: il cassetto è pronto.")
            }
        case .done:
            EmptyView()
        }
    }

    /// Velo pieno, senza buco: per i momenti in cui il bersaglio non ha
    /// ancora un rettangolo (camera in movimento, UI non ancora a schermo).
    /// Tiene l'overlay a schermo invece di farlo lampeggiare.
    private func velo(_ testo: String) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            tourBubble(testo)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .transition(.opacity)
    }

    /// Velatura bucata sul bersaglio: si vede scuro tutt'intorno, chiaro
    /// solo lì. Niente blocco dei tap: il bersaglio resta cliccabile
    /// esattamente come senza il fumetto sopra.
    private func spotlight(_ rect: CGRect, testo: String, ctaLabel: String? = nil, cta: (() -> Void)? = nil,
                            angolo: Angle = .zero, anche: CGRect? = nil, ancheAngolo: Angle = .zero) -> some View {
        ZStack {
            Color.black.opacity(0.5)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .frame(width: rect.width + 16, height: rect.height + 16)
                        .rotationEffect(angolo)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                )
                .overlay {
                    // secondo buco facoltativo: il post-it resta acceso
                    // insieme al bersaglio vero, così si vede sempre di
                    // cosa si sta parlando (icona/colore/salva) — ruotato
                    // come il post-it stesso, prima dello zoom
                    if let anche {
                        RoundedRectangle(cornerRadius: 10)
                            .frame(width: anche.width + 16, height: anche.height + 16)
                            .rotationEffect(ancheAngolo)
                            .position(x: anche.midX, y: anche.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            tourBubble(testo)
                .position(x: rect.midX, y: max(90, rect.minY - 46))

            if let ctaLabel, let cta {
                Button(ctaLabel, action: cta)
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .fixedSize()
                    .position(x: rect.midX, y: rect.maxY + 34)
            }
        }
        .transition(.opacity)
    }


    private func tourBubble(_ testo: String) -> some View {
        Text(testo)
            .font(Theme.mono(11))
            .lineSpacing(3)
            .foregroundStyle(Theme.paper)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: 240)
            .padding(14)
            .background(Theme.ink)
    }

    private func startCreation() {
        guard let cell = nextFreeCell else { return }
        createName = ""
        creatingCell = cell
    }

    /// Invio sulla targhetta: crea subito il progetto, senza popup. Il file
    /// nasce cifrato con la master password della sessione — è quella che hai
    /// digitato alla porta, non se ne chiede una per ogni progetto.
    private func confirmCreationName() {
        let name = createName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let key = MasterKey.session else {
            localError = "Hush è bloccato: riapri con la master password."
            return
        }
        newName = name
        newPassword = key
        createProject()
    }

    /// Cerca tra le password: apre il cassetto, sfoglia fino alla cartella
    /// che matcha e la estrae al centro. Se matcha un progetto, lo attiva.
    private func searchAndOpenEntry() {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return }
        if let hit = searchSuggestions.first {
            searchText = ""
            openEntry(project: hit.project, folder: hit.folder)
        } else if let match = projects.first(where: { $0.name.lowercased().contains(q) }) {
            searchText = ""
            openCell = cellIndex(for: match)
        }
    }

    // MARK: - Creazione progetto

    private func createProject() {
        guard newPassword.count >= 8 else { localError = "Master password troppo corta (minimo 8 caratteri)."; return }
        vm.createNew(name: newName, password: newPassword)
        let projectName = newName
        let icon = newIcon
        let note = newNoteColor
        // @MainActor esplicito: senza, dopo l'await il Task riprende su un
        // executor qualsiasi e le @State mutate qui sotto (openCell, sheet…)
        // arrivano alla UI in ritardo — sembra un tipo/nota "vecchio" finché
        // un altro render (es. digitare) non li aggiorna per davvero.
        Task { @MainActor in
            guard let bytes = await vm.save() else {
                showCreate = false
                return
            }
            do {
                // niente dialog di sistema: si salva subito nella cartella dell'app
                let url = VaultFileManager.shared.freeProjectURL(named: projectName)
                try Data(bytes).write(to: url, options: .atomic)
                try VaultFileManager.shared.addProject(name: projectName, url: url, icon: icon, noteColor: note)
                projects = VaultFileManager.shared.projects
                // subito dopo la creazione: apri il suo cassetto e la prima
                // password, così non tocca ripassare da menu/picker
                if let created = projects.first(where: { $0.path == url.path }) {
                    openCell = cellIndex(for: created)
                    newEntryProjectID = created.id
                    entryStep = .pickType
                    // progetto creato, cassetto che si apre: il tour finisce
                    // QUI, prima che creatingCell venga azzerato più sotto —
                    // aspettare il popup non andava: l'azzeramento faceva
                    // scattare il fallback "creazione annullata" e il tour
                    // ripartiva dal passo uno
                    if tourStep == .creaProgetto {
                        tourStep = .done
                        Preferences.vistoAiutoParete = true
                    }
                    // il cassetto si apre e si vede per un attimo prima che
                    // arrivi il popup delle categorie sopra: altrimenti il
                    // popup copre subito tutto e l'apertura non si vede mai
                    Task {
                        try? await Task.sleep(for: .seconds(0.6))
                        showEntryFlow = true
                    }
                }
            } catch {
                localError = "Salvataggio non riuscito: \(error.localizedDescription)"
            }
            showCreate = false
            newName = ""; newPassword = ""; newIcon = nil
            newNoteColor = ProjectsHomeView.noteColors.first
            creatingCell = nil; createName = ""
        }
    }

    // MARK: - Apertura progetto (vault reale)

    private func openProject(_ project: VaultFileManager.Project) {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: project.path))
            pendingOpenData = Array(data)
            openingProject = project
            showOpenPasswordSheet = true
        } catch {
            localError = "Impossibile leggere il progetto: \(error.localizedDescription)"
        }
    }

    private var openPasswordSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            IndexLabel(text: openingProject?.name ?? "Progetto")
            SecureField("Master password", text: $openPassword)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit { attemptOpen() }
            if vm.isBusy {
                ProgressView("Decifro il vault…").font(Theme.mono(11)).tint(Theme.ink)
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
        guard let data = pendingOpenData, let project = openingProject else { return }
        Task { @MainActor in
            await vm.open(fileData: data, password: openPassword)
            openPassword = ""
            if vm.isUnlocked {
                try? VaultFileManager.shared.selectProject(project)
                showOpenPasswordSheet = false
            } else if let err = vm.errorMessage {
                localError = err
                vm.errorMessage = nil
            }
        }
    }

}

/// Scheda della password: esce animata dal cassetto (parte bassa e piccola,
/// sale al centro) e supporta la modifica dei campi in-place.
/// Scheda per i tipi diversi da login/password (nota sicura, carta, identità,
/// documento): stessi campi salvati in creazione, modificabili in-place.
struct GenericEntryCard: View {
    let number: Int
    let name: String
    let icon: String
    @State var rows: [ProjectsHomeView.CustomField]
    let onSave: ([ProjectsHomeView.CustomField]) -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    /// "Annulla" in modifica torna a questi, senza chiudere la cartella.
    private let originalRows: [ProjectsHomeView.CustomField]

    init(number: Int, name: String, icon: String, rows: [ProjectsHomeView.CustomField],
         onSave: @escaping ([ProjectsHomeView.CustomField]) -> Void,
         onClose: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.number = number
        self.name = name
        self.icon = icon
        _rows = State(initialValue: rows)
        self.onSave = onSave
        self.onClose = onClose
        self.onDelete = onDelete
        originalRows = rows
    }

    @State private var editing = false
    @State private var shown = false
    @State private var scrolled = false
    @State private var atBottom = true

    var body: some View {
        VStack(spacing: 18) {
            if rows.allSatisfy({ $0.value.isEmpty }) && !editing {
                Text("Nessun dato")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxHeight: .infinity)
            } else {
                // la cartella cresce fin dove può; oltre quel punto si scrolla
                GeometryReader { outer in
                ScrollView {
                    VStack(spacing: 12) {
                        GeometryReader { g in
                            Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("scrollGeneric")).minY)
                        }
                        .frame(height: 0)
                        ForEach($rows) { $field in
                            if editing {
                                HStack(spacing: 8) {
                                    TextField("Etichetta", text: $field.label)
                                        .textFieldStyle(.plain)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkSoft)
                                        .frame(width: 90, alignment: .leading)
                                    TextField("Valore", text: $field.value)
                                        .textFieldStyle(.plain)
                                        .font(Theme.mono(12, .semibold))
                                        .foregroundStyle(Theme.ink)
                                    Button {
                                        rows.removeAll { $0.id == field.id }
                                    } label: {
                                        Image(systemName: "minus.circle")
                                            .foregroundStyle(Theme.danger)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .themedRow()
                            } else if !field.value.isEmpty {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(field.label)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkSoft)
                                        .frame(width: 90, alignment: .leading)
                                    Text(field.value)
                                        .font(Theme.mono(12, .semibold))
                                        .foregroundStyle(Theme.ink)
                                        .textSelection(.enabled)
                                    Spacer(minLength: 0)
                                    CopyButton(text: field.value)
                                }
                                .themedRow()
                            }
                        }

                        if editing {
                            Button { rows.append(ProjectsHomeView.CustomField()) } label: {
                                Label("Aggiungi un campo", systemImage: "plus")
                            }
                            .buttonStyle(.plain)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                        }

                        GeometryReader { g in
                            Color.clear.preference(key: ScrollBottomKey.self, value: g.frame(in: .named("scrollGeneric")).maxY)
                        }
                        .frame(height: 0)
                    }
                }
                .coordinateSpace(name: "scrollGeneric")
                .onPreferenceChange(ScrollOffsetKey.self) { y in scrolled = y < -4 }
                .onPreferenceChange(ScrollBottomKey.self) { y in atBottom = y <= outer.size.height + 4 }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
                .scrollFade(top: scrolled, bottom: !atBottom)
                }
            }

            // in modifica il tasto che conta è "salva": va a destra, in
            // evidenza, dove prima stava "chiudi"
            HStack(spacing: 10) {
                if editing {
                    Button("Elimina") { onDelete() }
                        .buttonStyle(OutlineButtonStyle(danger: true))

                    Button("Salva") {
                        rows = rows.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                        onSave(rows)
                        editing = false
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
                } else {
                    Button("Modifica") { editing = true }
                        .buttonStyle(OutlineButtonStyle())

                    Button("Chiudi") { onClose() }
                        .buttonStyle(InkButtonStyle(prominent: true))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
        }
    }
}

private extension View {
    /// Fondo di carta steso su TUTTA la finestra della sheet.
    ///
    /// Mettere lo sfondo solo dietro al contenuto non basta: se la finestra
    /// è più grande, o mentre si sta ancora dimensionando, nella parte
    /// scoperta si vede il fondo di sistema — su tema scuro un rettangolo
    /// nero, che sbuca per un istante alla presentazione.
    func sheetPaper() -> some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            self
        }
        .preferredColorScheme(.light)
    }

    func themedRow() -> some View {
        padding(10)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

struct EntryCard: View {
    let number: Int
    let name: String
    @State var user: String
    @State var password: String
    @State var url: String
    @State var notes: String
    /// Url in più e campi personalizzati messi in creazione: in modifica
    /// devono ricomparire tutti, e se ne possono aggiungere altri.
    @State var extras: [ProjectsHomeView.CustomField]
    let onSave: (String, String, String, String, [ProjectsHomeView.CustomField]) -> Void
    let onClose: () -> Void
    let onDelete: () -> Void

    /// Copie intatte: "Annulla" in modifica deve tornare a questi valori,
    /// non chiudere la cartella — si resta dentro, solo senza le modifiche.
    private let originalUser: String
    private let originalPassword: String
    private let originalUrl: String
    private let originalNotes: String
    private let originalExtras: [ProjectsHomeView.CustomField]

    init(number: Int, name: String, user: String, password: String, url: String, notes: String,
         extras: [ProjectsHomeView.CustomField],
         onSave: @escaping (String, String, String, String, [ProjectsHomeView.CustomField]) -> Void,
         onClose: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.number = number
        self.name = name
        _user = State(initialValue: user)
        _password = State(initialValue: password)
        _url = State(initialValue: url)
        _notes = State(initialValue: notes)
        _extras = State(initialValue: extras)
        self.onSave = onSave
        self.onClose = onClose
        self.onDelete = onDelete
        originalUser = user
        originalPassword = password
        originalUrl = url
        originalNotes = notes
        originalExtras = extras
    }

    @State private var editing = false
    @State private var revealPassword = false
    @State private var copiedPassword = false
    @State private var scrolled = false
    @State private var atBottom = true
    @State private var shown = false

    var body: some View {
        // Nessuno sfondo: la "scheda" È la cartella 3D estratta al centro —
        // qui appaiono solo i dati, dentro il corpo della cartella.
        VStack(spacing: 18) {
            GeometryReader { outer in
            ScrollView {
                VStack(spacing: 12) {
                    GeometryReader { g in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named("scrollEntry")).minY)
                    }
                    .frame(height: 0)
                    if editing || !user.isEmpty {
                        fieldRow("Utente", value: $user)
                    }
                    if editing || !password.isEmpty {
                        passwordRow
                    }
                    if editing || !url.isEmpty {
                        fieldRow("Url", value: $url)
                    }

                    ForEach($extras) { $field in
                        if editing {
                            HStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    TextField("Etichetta", text: $field.label)
                                        .textFieldStyle(.plain)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkSoft)
                                        .frame(width: 90, alignment: .leading)
                                    TextField("Valore", text: $field.value)
                                        .textFieldStyle(.plain)
                                        .font(Theme.mono(12, .semibold))
                                        .foregroundStyle(Theme.ink)
                                }
                                .themedRow()
                                Button {
                                    extras.removeAll { $0.id == field.id }
                                } label: {
                                    Image(systemName: "minus.circle").foregroundStyle(Theme.danger)
                                }
                                .buttonStyle(.plain)
                            }
                        } else if !field.value.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                Text(field.label)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.inkSoft)
                                    .frame(width: 90, alignment: .leading)
                                Text(field.value)
                                    .font(Theme.mono(12, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .textSelection(.enabled)
                                Spacer(minLength: 0)
                                CopyButton(text: field.value)
                            }
                            .themedRow()
                        }
                    }

                    if editing || !notes.isEmpty {
                        fieldRow("Note", value: $notes)
                    }

                    if editing {
                        Button { extras.append(ProjectsHomeView.CustomField()) } label: {
                            Label("Aggiungi un campo", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)
                    }

                    GeometryReader { g in
                        Color.clear.preference(key: ScrollBottomKey.self, value: g.frame(in: .named("scrollEntry")).maxY)
                    }
                    .frame(height: 0)
                }
            }
            .coordinateSpace(name: "scrollEntry")
            .onPreferenceChange(ScrollOffsetKey.self) { y in scrolled = y < -4 }
            .onPreferenceChange(ScrollBottomKey.self) { y in atBottom = y <= outer.size.height + 4 }
            .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.hidden)
            .scrollFade(top: scrolled, bottom: !atBottom)
            }
            // niente Spacer qui: sarebbe flessibile quanto la ScrollView e si
            // spartirebbero lo spazio a metà — è per questo che l'area dei
            // campi restava piccola pur avendo tutta la cartella a disposizione.
            // La ScrollView da sola si prende tutto e spinge i bottoni in fondo.

            // in modifica il tasto che conta è "salva": va a destra, in evidenza
            HStack(spacing: 10) {
                if editing {
                    Button("Elimina") { onDelete() }
                        .buttonStyle(OutlineButtonStyle(danger: true))

                    Button("Salva") {
                        onSave(user, password, url, notes,
                               extras.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
                        editing = false
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
                } else {
                    Button("Modifica") { editing = true }
                        .buttonStyle(OutlineButtonStyle())

                    if password.isEmpty {
                        Button("Chiudi") { onClose() }
                            .buttonStyle(InkButtonStyle(prominent: true))
                    } else {
                        Button(copiedPassword ? "Copiata" : "Copia password") {
                            copyToClipboard(password)
                            copiedPassword = true
                            // il feedback si vede un attimo prima che la
                            // cartella si richiuda, non sparisce col resto
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { onClose() }
                        }
                        .buttonStyle(InkButtonStyle(prominent: true))
                        .disabled(copiedPassword)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .opacity(shown ? 1 : 0)
        .onAppear {
            // il rect arriva a estrazione finita: qui basta un fade veloce
            withAnimation(.easeOut(duration: 0.25)) { shown = true }
        }
    }

    private func fieldRow(_ label: String, value: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 90, alignment: .leading)
            if editing {
                TextField("", text: value)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(6)
                    .background(Theme.paperRaised)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            } else {
                Text(value.wrappedValue)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                CopyButton(text: value.wrappedValue)
            }
        }
        .themedRow()
    }

    private var passwordRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Password")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .frame(width: 90, alignment: .leading)
            if editing {
                TextField("", text: $password)
                    .textFieldStyle(.plain)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(6)
                    .background(Theme.paperRaised)
                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
            } else {
                Text(revealPassword ? password : String(repeating: "•", count: password.count))
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button {
                    revealPassword.toggle()
                } label: {
                    Image(systemName: revealPassword ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                CopyButton(text: password)
            }
        }
        .themedRow()
    }
}

/// Picker icone a schermo intero: ricerca + griglia di tutta la libreria.
struct IconLibrarySheet: View {
    let selected: String?
    @Binding var search: String
    let library: [String]
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 8)

    private var filtered: [String] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return library }
        return library.filter { $0.contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            IndexLabel(text: "Scegli icona")

            TextField("Cerca…", text: $search)
                .textFieldStyle(PaperFieldStyle())

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            onPick(name)
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(selected == name ? Theme.paper : Theme.ink)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(selected == name ? Theme.ink : Theme.paperRaised)
                                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 320)

            Button("Chiudi") { dismiss() }
                .buttonStyle(OutlineButtonStyle())
                .frame(width: 120)
        }
        .padding(26)
        .frame(width: 460)
        .background(Theme.paper)
        .preferredColorScheme(.light)
    }
}
#endif
