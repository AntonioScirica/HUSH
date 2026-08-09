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

    @EnvironmentObject var vm: VaultViewModel

    @State private var projects: [VaultFileManager.Project] = VaultFileManager.shared.projects
    /// Cella con il cassetto aperto — resta lì dov'è, non si sposta mai al centro.
    @State private var openCell: Int?
    private var drawerOpen: Bool { openCell != nil }
    @State private var searchText = ""
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
    /// Modifiche fatte dalla scheda, in memoria (finché non c'è il vault vero).
    @State private var entryOverrides: [String: (user: String, password: String, url: String, notes: String)] = [:]

    @State private var showCreate = false
    @State private var newName = ""
    @State private var newPassword = ""
    @State private var newIcon: String?
    @State private var newNoteColor: String? = ProjectsHomeView.noteColors.first
    /// Modalità modifica di un progetto esistente (vs creazione).
    @State private var isEditingProject = false
    @State private var editingProjectID: String?
    @State private var showDeleteConfirm = false
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

    // ponytail: voci finte solo per prototipare l'apertura del cassetto —
    // da sostituire con vm.store.allEntries quando il vault reale è collegato qui.
    // Una lista per progetto: un cassetto nuovo parte vuoto, non eredita
    // quelle di un altro (prima era un unico array condiviso da tutti).
    @State private var entriesByProject: [String: [String]] = [:]
    /// Un solo sheet per tutto il flusso "nuova voce": passare da categoria
    /// a modulo cambia solo `entryStep`, non chiude/riapre un secondo sheet
    /// — quello causava un frame con la categoria vecchia prima di aggiornarsi.
    @State private var showEntryFlow = false
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

    enum EntryKind: String {
        case login, secureNote, card, identity, password, document

        var label: String {
            switch self {
            case .login: return "accesso"
            case .secureNote: return "nota sicura"
            case .card: return "carta di credito"
            case .identity: return "identità"
            case .password: return "password"
            case .document: return "documento"
            }
        }
        var icon: String {
            switch self {
            case .login: return "person.crop.circle.badge.checkmark"
            case .secureNote: return "note.text"
            case .card: return "creditcard"
            case .identity: return "person.text.rectangle"
            case .password: return "key"
            case .document: return "doc"
            }
        }
    }

    /// Voce → tipo con cui è stata creata (per sapere come mostrarla).
    @State private var entryKinds: [String: EntryKind] = [:]
    /// Voce → campi salvati, etichetta/valore, nell'ordine in cui li vede
    /// l'utente. Copre i tipi diversi da "accesso"/"password", che usano
    /// invece `entryOverrides` (ha già un editor dedicato, EntryCard).
    @State private var entryDetails: [String: [(label: String, value: String)]] = [:]
    /// Voce "documento" → percorso locale del file allegato (copiato, non
    /// un riferimento all'originale: non si perde se sposti/cancelli quello).
    @State private var entryAttachments: [String: URL] = [:]

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
        guard let folder = selectedFolder, folder >= 1, folder - 1 < openEntries.count else { return 3 }
        let name = openEntries[folder - 1]
        switch entryKinds[name] ?? .login {
        case .login, .password:
            // utente + password + url + note (in modifica c'è sempre) + extra
            return 4 + (entryDetails[name]?.count ?? 0)
        default:
            return max(1, entryDetails[name]?.count ?? 1)
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
        guard let folder = selectedFolder, folder >= 1, folder - 1 < openEntries.count else { return false }
        let kind = entryKinds[openEntries[folder - 1]] ?? .login
        return kind == .login || kind == .password
    }

    /// Voci del cassetto aperto (vuoto se nessuno, o progetto senza voci).
    private var openEntries: [String] {
        guard let id = openProjectEntry?.id else { return [] }
        return entriesByProject[id] ?? []
    }

    /// Voci per ogni cella della parete, nello stesso ordine di `cellLabels`.
    private var cellEntries: [[String]] {
        let assignments = projectAtCell
        return (0..<(cols * rows)).map { assignments[$0].flatMap { entriesByProject[$0.id] } ?? [] }
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
                if drawerOpen {
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
            .animation(.easeOut(duration: 0.45), value: chromeVisible)
            .animation(.easeOut(duration: 0.25), value: drawerOpen)

            VStack {
                // sono i comandi del PROGETTO: con una cartella estratta
                // c'è la sua scheda a comandare, questi sparirebbero sotto
                if drawerOpen && selectedFolder == nil {
                    HStack(spacing: 10) {
                        Button("modifica") { startEditingOpenProject() }
                            .buttonStyle(OutlineButtonStyle())
                            .frame(width: 110)
                        Button("chiudi") { openCell = nil }
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
                                TextField("cerca…", text: $searchText)
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
            .animation(.easeOut(duration: 0.45), value: chromeVisible)
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
                if selectedFolder != nil { selectedFolder = nil }
            }

            // agli angoli, staccati dalla barra centrale: chiudere a sinistra,
            // impostazioni a destra
            if !drawerOpen && creatingCell == nil {
                VStack {
                    Spacer()
                    HStack {
                        cornerButton("lock", help: "Richiudi lo scrigno") { onLock() }
                        Spacer()
                        cornerButton("gearshape", help: "Impostazioni") { showSettings = true }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .opacity(chromeVisible ? 1 : 0)
            .animation(.easeOut(duration: 0.45), value: chromeVisible)
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
                                Button("annulla") { endEditing() }
                                    .buttonStyle(OutlineButtonStyle())
                            } else {
                                Button(isEditingProject ? "salva" : "crea progetto") {
                                    isEditingProject ? saveEditedProject() : confirmCreationName()
                                }
                                .buttonStyle(InkButtonStyle(prominent: true))

                                if isEditingProject {
                                    Button("elimina progetto") { showDeleteConfirm = true }
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
                    Button(newIcon == nil ? "scegli icona" : "cambia icona") {
                        showIconLibrary = true
                    }
                    .buttonStyle(OutlineButtonStyle())

                    HStack(spacing: 10) {
                        Button("annulla") {
                            newIcon = nil
                            focusNote = false
                        }
                        .buttonStyle(OutlineButtonStyle())

                        Button("fatto") { focusNote = false }
                            .buttonStyle(InkButtonStyle(prominent: true))
                    }
                }
                .frame(width: 230)
                .position(x: note.midX, y: note.maxY + 70)
            }

            // dati sovrapposti ESATTAMENTE al corpo della cartella estratta
            // (rettangolo proiettato dalla scena 3D — sono la stessa cosa)
            if let folder = selectedFolder, folder >= 1, folder - 1 < openEntries.count,
               let rect = folderRect {
                let name = openEntries[folder - 1]
                let kind = entryKinds[name] ?? .login

                if kind == .login || kind == .password {
                    let host = name.replacingOccurrences(of: " ", with: "")
                    let saved = entryOverrides[name]
                    EntryCard(
                        number: folder,
                        name: name,
                        user: saved?.user ?? "antonio@\(host).com",
                        password: saved?.password ?? "scrigno-\(host)-24",
                        url: saved?.url ?? "https://\(host).com",
                        notes: saved?.notes ?? "",
                        extras: (entryDetails[name] ?? []).map {
                            var f = CustomField(); f.label = $0.label; f.value = $0.value; return f
                        },
                        onSave: { u, p, r, n, extras in
                            // ponytail: override in memoria — si salva nel vault reale quando collegato.
                            entryOverrides[name] = (u, p, r, n)
                            entryDetails[name] = extras.map {
                                (label: $0.label.isEmpty ? "campo" : $0.label, value: $0.value)
                            }
                        },
                        onClose: { selectedFolder = nil }
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
                        name: name,
                        icon: kind.icon,
                        rows: (entryDetails[name] ?? []).map {
                            var f = CustomField(); f.label = $0.label; f.value = $0.value; return f
                        },
                        onSave: { rows in
                            entryDetails[name] = rows.map {
                                (label: $0.label.isEmpty ? "campo" : $0.label, value: $0.value)
                            }
                        },
                        onClose: { selectedFolder = nil }
                    )
                    // margini veri dentro il corpo della cartella: prima il
                    // contenuto arrivava a filo dei bordi e sembrava stare
                    // fuori invece che dentro
                    .frame(width: rect.width * 0.82, height: rect.height * 0.78)
                    .position(x: rect.midX, y: rect.midY + rect.height * 0.04)
                    .id(folder)
                }
            }
        }
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
        .sheet(isPresented: $showSettings) {
            SettingsView(onClose: { showSettings = false },
                         onImport: { consumePendingImport() })
                .sheetPaper()
        }
        .sheet(isPresented: $showIconLibrary) {
            IconLibrarySheet(selected: newIcon, search: $iconSearch, library: iconLibrary) { picked in
                newIcon = (newIcon == picked ? nil : picked)
                showIconLibrary = false
            }
            .sheetPaper()
        }
        .alert("Errore", isPresented: .constant(localError != nil), actions: {
            Button("OK") { localError = nil }
        }, message: { Text(localError ?? "") })
        .alert("Eliminare il progetto?", isPresented: $showDeleteConfirm, actions: {
            Button("annulla", role: .cancel) {}
            Button("elimina", role: .destructive) { deleteEditedProject() }
        }, message: { Text("Il file .kdbx viene cancellato dal disco. Non si può annullare.") })
        .onAppear {
            projects = VaultFileManager.shared.projects
            consumePendingImport()
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
                // schede, che sono indicizzate per titolo
                var used = Set<String>()
                var titles: [String] = []
                for entry in imported {
                    var title = entry.title
                    var n = 2
                    while used.contains(title) { title = "\(entry.title) (\(n))"; n += 1 }
                    used.insert(title)
                    titles.append(title)
                    entryKinds[title] = .login
                    entryOverrides[title] = (user: entry.username,
                                             password: entry.password,
                                             url: entry.url,
                                             notes: entry.notes)
                }
                entriesByProject[created.id] = titles
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
        return projects.flatMap { p -> [(project: VaultFileManager.Project, folder: Int, name: String)] in
            (entriesByProject[p.id] ?? []).enumerated()
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
        if openCell != cell { openCell = cell }
        selectedFolder = folder
    }

    private static let entryTypeOrder: [EntryKind] = [.login, .secureNote, .card, .identity, .password, .document]

    private var entryTypePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("cosa vuoi creare?")
                .font(Theme.mono(13))
                .foregroundStyle(Theme.ink)
                .padding(.top, 40)

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

            Button("annulla") {
                showEntryFlow = false
            }
            .buttonStyle(OutlineButtonStyle())
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var newEntrySheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            IndexLabel(number: (entriesByProject[newEntryProjectID ?? ""]?.count ?? 0) + 1, text: "nuovo · \(newEntryKind.label)")
                .padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // progetto: scelto prima di entrare qui, ma cambiabile senza uscire
                    Menu {
                        ForEach(projects) { p in
                            Button(p.name.lowercased()) { newEntryProjectID = p.id }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: currentNewEntryProject?.icon ?? "folder")
                                .font(.system(size: 12))
                            Text((currentNewEntryProject?.name ?? "progetto").lowercased())
                                .font(Theme.mono(12, .semibold))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.inkSoft)
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(10)
                        .background(Theme.paperRaised)
                        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(projects.count <= 1)

                    // Il titolo è il nome della CARTELLA, non un campo come
                    // gli altri: sta in cima, staccato, con la sua etichetta.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("nome della cartella")
                            .font(Theme.mono(10, .semibold))
                            .tracking(1.2)
                            .textCase(.uppercase)
                            .foregroundStyle(Theme.inkSoft)
                        AutoFocusField(placeholder: "titolo", text: $newEntryName)
                    }

                    Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)
                        .padding(.vertical, 2)

                    Text("cosa c'è dentro")
                        .font(Theme.mono(10, .semibold))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.inkSoft)

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
                        TextField("note", text: $newEntryNotes, axis: .vertical)
                            .textFieldStyle(PaperFieldStyle())
                            .lineLimit(3...5)
                    }
                }
                .padding(.trailing, 4)   // spazio per la scrollbar
            }
            .frame(maxHeight: .infinity)

            if !newEntryName.trimmingCharacters(in: .whitespaces).isEmpty && !newEntryHasContent {
                Text("serve almeno un dato oltre al titolo")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
            }

            HStack(spacing: 10) {
                Button("annulla") { resetNewEntryForm() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(width: 120)
                Button("crea") { confirmNewEntry() }
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
        TextField("utente / email", text: $newEntryUser)
            .textFieldStyle(PaperFieldStyle())

        HStack(spacing: 8) {
            Group {
                if revealNewEntryPassword {
                    TextField("password", text: $newEntryPassword)
                } else {
                    SecureField("password", text: $newEntryPassword)
                }
            }
            .textFieldStyle(PaperFieldStyle())

            Button { revealNewEntryPassword.toggle() } label: {
                Image(systemName: revealNewEntryPassword ? "eye.slash" : "eye")
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)

            Button { newEntryPassword = Self.randomPassword() } label: {
                Image(systemName: "die.face.5")
                    .foregroundStyle(Theme.inkSoft)
            }
            .buttonStyle(.plain)
            .help("Genera password")
        }

        // url: più di uno, come i "siti web" di 1Password
        VStack(alignment: .leading, spacing: 8) {
            ForEach($newEntryURLs) { $url in
                HStack(spacing: 8) {
                    TextField("url", text: $url.value)
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
                Label("aggiungi un altro url", systemImage: "plus")
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
                    TextField("etichetta", text: $field.label)
                        .textFieldStyle(PaperFieldStyle())
                        .frame(width: 110)
                    Group {
                        if field.isSecret {
                            SecureField("valore", text: $field.value)
                        } else {
                            TextField("valore", text: $field.value)
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
                Label("aggiungi un campo", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.inkSoft)
        }
    }

    @ViewBuilder private var cardFields: some View {
        TextField("intestatario", text: $newCardHolder)
            .textFieldStyle(PaperFieldStyle())
        TextField("numero carta", text: $newCardNumber)
            .textFieldStyle(PaperFieldStyle())
        HStack(spacing: 8) {
            TextField("scadenza (MM/AA)", text: $newCardExpiry)
                .textFieldStyle(PaperFieldStyle())
                // la barra la mette lui dopo il mese: si scrivono solo i numeri
                .onChange(of: newCardExpiry) { _, v in
                    let formatted = Self.formatExpiry(v)
                    if formatted != v { newCardExpiry = formatted }
                }
            TextField("cvv", text: $newCardCVV)
                .textFieldStyle(PaperFieldStyle())
                .frame(width: 90)
                // solo cifre, al massimo quattro: tre sulla gran parte dei
                // circuiti, quattro su American Express
                .onChange(of: newCardCVV) { _, v in
                    let digits = String(v.filter(\.isNumber).prefix(4))
                    if digits != v { newCardCVV = digits }
                }
        }
        TextField("pin", text: $newCardPIN)
            .textFieldStyle(PaperFieldStyle())
    }

    @ViewBuilder private var identityFields: some View {
        HStack(spacing: 8) {
            TextField("nome", text: $newIdentityFirstName)
                .textFieldStyle(PaperFieldStyle())
            TextField("cognome", text: $newIdentityLastName)
                .textFieldStyle(PaperFieldStyle())
        }
        TextField("indirizzo", text: $newIdentityAddress)
            .textFieldStyle(PaperFieldStyle())
        TextField("telefono", text: $newIdentityPhone)
            .textFieldStyle(PaperFieldStyle())
        TextField("email", text: $newIdentityEmail)
            .textFieldStyle(PaperFieldStyle())
    }

    /// File leggero allegato: copiato negli allegati dell'app alla creazione,
    /// così resta raggiungibile anche se l'originale sparisce.
    @ViewBuilder private var secureNoteFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array($newSecureNotes.enumerated()), id: \.element.id) { i, $note in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("titolo della nota \(i + 1)", text: $note.label)
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
                    TextField("testo", text: $note.value, axis: .vertical)
                        .textFieldStyle(PaperFieldStyle())
                        .lineLimit(3...6)
                }
            }
            Button { newSecureNotes.append(CustomField()) } label: {
                Label("aggiungi un'altra nota", systemImage: "plus")
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
                Label("scegli file…", systemImage: "doc.badge.plus")
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
        newEntryName = ""; newEntryUser = ""; newEntryPassword = ""
        newEntryURLs = [IdentifiedString()]; newEntryFields = []; newEntryNotes = ""
        newSecureNotes = [CustomField()]
        revealNewEntryPassword = false
        newCardHolder = ""; newCardNumber = ""; newCardExpiry = ""; newCardCVV = ""; newCardPIN = ""
        newIdentityFirstName = ""; newIdentityLastName = ""; newIdentityAddress = ""
        newIdentityPhone = ""; newIdentityEmail = ""
        pendingDocumentURL = nil
    }

    /// Aggiunge la voce finta e chiude il modulo — niente apertura/animazione
    /// del cassetto: solo la schermata di creazione, come richiesto. I campi
    /// salvati dipendono dal tipo: login/password hanno l'editor dedicato
    /// (EntryCard, con `entryOverrides`); gli altri finiscono in una lista
    /// etichetta/valore generica (`entryDetails`), mostrata in sola lettura.
    private func confirmNewEntry() {
        let name = newEntryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let projectID = newEntryProjectID else { return }
        entryKinds[name] = newEntryKind

        switch newEntryKind {
        case .login, .password:
            entryOverrides[name] = (
                user: newEntryUser,
                password: newEntryPassword.isEmpty ? Self.randomPassword() : newEntryPassword,
                url: newEntryURLs.first?.value ?? "",
                notes: newEntryNotes
            )
            // url in più e campi personalizzati: vanno conservati, o in
            // modifica sparirebbero pezzi di quel che avevi inserito
            var extras: [(label: String, value: String)] = []
            extras += newEntryURLs.dropFirst()
                .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ("url", $0.value) }
            extras += newEntryFields
                .filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { ($0.label.isEmpty ? "campo" : $0.label, $0.value) }
            entryDetails[name] = extras
        case .secureNote:
            entryDetails[name] = newSecureNotes.enumerated()
                .filter { !$0.element.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { i, note in
                    let title = note.label.trimmingCharacters(in: .whitespaces)
                    return (title.isEmpty ? "nota \(i + 1)" : title, note.value)
                }
        case .card:
            entryDetails[name] = [
                ("intestatario", newCardHolder),
                ("numero carta", newCardNumber),
                ("scadenza", newCardExpiry),
                ("cvv", newCardCVV),
                ("pin", newCardPIN),
                ("note", newEntryNotes)
            ].filter { !$0.1.isEmpty }
        case .identity:
            entryDetails[name] = [
                ("nome", newIdentityFirstName),
                ("cognome", newIdentityLastName),
                ("indirizzo", newIdentityAddress),
                ("telefono", newIdentityPhone),
                ("email", newIdentityEmail),
                ("note", newEntryNotes)
            ].filter { !$0.1.isEmpty }
        case .document:
            var fields = [("note", newEntryNotes)].filter { !$0.1.isEmpty }
            if let src = pendingDocumentURL {
                do {
                    let saved = try VaultFileManager.shared.storeAttachment(from: src)
                    entryAttachments[name] = saved
                    fields.insert(("file", src.lastPathComponent), at: 0)
                } catch {
                    localError = "Impossibile allegare il file: \(error.localizedDescription)"
                }
            }
            entryDetails[name] = fields
        }

        resetNewEntryForm()   // chiude il modulo

        // La voce in più fa ricostruire la scena 3D (una cartella nuova nel
        // cassetto): farlo mentre la sheet si sta chiudendo dava un lampo
        // nero. Prima si chiude, poi si tocca la scena.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            entriesByProject[projectID, default: []].append(name)
            // appena creata si alza nel nastro, come arrivandoci scrollando
            if let project = projects.first(where: { $0.id == projectID }) {
                let cell = cellIndex(for: project)
                if openCell != cell { openCell = cell }
                revealFolder = entriesByProject[projectID]?.count
            }
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
        entriesByProject[id] = nil
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
            localError = "Scrigno è bloccato: riapri con la master password."
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
                    showEntryFlow = true
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
            IndexLabel(number: 1, text: openingProject?.name ?? "progetto")
            SecureField("master password", text: $openPassword)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit { attemptOpen() }
            if vm.isBusy {
                ProgressView("Decifro il vault…").font(Theme.mono(11)).tint(Theme.ink)
            }
            HStack(spacing: 10) {
                Button("annulla") {
                    showOpenPasswordSheet = false
                    openPassword = ""
                }
                .buttonStyle(OutlineButtonStyle())
                .frame(width: 110)
                Button("apri") { attemptOpen() }
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

    @State private var editing = false
    @State private var shown = false

    var body: some View {
        VStack(spacing: 18) {
            if rows.isEmpty && !editing {
                Text("nessun dato")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(maxHeight: .infinity)
            } else {
                // la cartella cresce fin dove può; oltre quel punto si scrolla
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach($rows) { $field in
                            if editing {
                                HStack(spacing: 8) {
                                    TextField("etichetta", text: $field.label)
                                        .textFieldStyle(.plain)
                                        .font(Theme.mono(11))
                                        .foregroundStyle(Theme.inkSoft)
                                        .frame(width: 90, alignment: .leading)
                                    TextField("valore", text: $field.value)
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
                            } else {
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
                                Label("aggiungi un campo", systemImage: "plus")
                            }
                            .buttonStyle(.plain)
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity)
            }

            // in modifica il tasto che conta è "salva": va a destra, in
            // evidenza, dove prima stava "chiudi"
            HStack(spacing: 10) {
                if editing {
                    Button("chiudi") { onClose() }
                        .buttonStyle(OutlineButtonStyle())

                    Button("salva") {
                        rows = rows.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                        onSave(rows)
                        editing = false
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
                } else {
                    Button("modifica") { editing = true }
                        .buttonStyle(OutlineButtonStyle())

                    Button("chiudi") { onClose() }
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

    @State private var editing = false
    @State private var revealPassword = false
    @State private var shown = false

    var body: some View {
        // Nessuno sfondo: la "scheda" È la cartella 3D estratta al centro —
        // qui appaiono solo i dati, dentro il corpo della cartella.
        VStack(spacing: 18) {
            ScrollView {
                VStack(spacing: 12) {
                    fieldRow("utente", value: $user)
                    passwordRow
                    fieldRow("url", value: $url)

                    ForEach($extras) { $field in
                        if editing {
                            HStack(spacing: 8) {
                                TextField("etichetta", text: $field.label)
                                    .textFieldStyle(.plain)
                                    .font(Theme.mono(11))
                                    .foregroundStyle(Theme.inkSoft)
                                    .frame(width: 90, alignment: .leading)
                                TextField("valore", text: $field.value)
                                    .textFieldStyle(.plain)
                                    .font(Theme.mono(12, .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .padding(6)
                                    .background(Theme.paperRaised)
                                    .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
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
                        }
                    }

                    if editing || !notes.isEmpty {
                        fieldRow("note", value: $notes)
                    }

                    if editing {
                        Button { extras.append(ProjectsHomeView.CustomField()) } label: {
                            Label("aggiungi un campo", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // niente Spacer qui: sarebbe flessibile quanto la ScrollView e si
            // spartirebbero lo spazio a metà — è per questo che l'area dei
            // campi restava piccola pur avendo tutta la cartella a disposizione.
            // La ScrollView da sola si prende tutto e spinge i bottoni in fondo.

            // in modifica il tasto che conta è "salva": va a destra, in evidenza
            HStack(spacing: 10) {
                if editing {
                    Button("chiudi") { onClose() }
                        .buttonStyle(OutlineButtonStyle())

                    Button("salva") {
                        onSave(user, password, url, notes,
                               extras.filter { !$0.value.trimmingCharacters(in: .whitespaces).isEmpty })
                        editing = false
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
                } else {
                    Button("modifica") { editing = true }
                        .buttonStyle(OutlineButtonStyle())

                    Button("copia password") {
                        copyToClipboard(password)
                        onClose()
                    }
                    .buttonStyle(InkButtonStyle(prominent: true))
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
    }

    private var passwordRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("password")
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
                Text(revealPassword ? password : String(repeating: "•", count: max(password.count, 8)))
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
                }
                .buttonStyle(.plain)
                CopyButton(text: password)
            }
        }
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
            IndexLabel(number: 1, text: "scegli icona")

            TextField("cerca…", text: $search)
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

            Button("chiudi") { dismiss() }
                .buttonStyle(OutlineButtonStyle())
                .frame(width: 120)
        }
        .padding(26)
        .frame(width: 460)
        .background(Theme.paper)
        .preferredColorScheme(.light)
    }
}
