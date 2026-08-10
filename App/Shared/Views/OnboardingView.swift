import SwiftUI
import UniformTypeIdentifiers
import VaultCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private extension View {
    func themedImportRow() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Primo avvio: si presenta Hush, si sceglie la master password e —
/// se la macchina ce l'ha — si attiva il dito. Stessa carta, stesso
/// inchiostro, stessi divider numerati del resto dell'app.
struct OnboardingView: View {
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        #if os(iOS)
        // sul telefono il collegamento col Mac viene subito dopo il
        // benvenuto: chi scarica l'app di solito ha già i cassetti di là,
        // e la password che imposta tra un attimo dovrà essere la stessa
        // usata sul Mac — non ha senso chiederla prima di dirlo.
        case intro, mac, password, recovery, biometry, importing, ready
        #else
        case intro, password, recovery, biometry, importing, ready
        #endif
    }

    @State private var step: Step = .intro
    @State private var password = ""
    @State private var confirm = ""
    @State private var reveal = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool

    @State private var showFileImporter = false
    @State private var importedCount = 0
    #if os(iOS)
    /// Importazione dei cassetti esportati dal Mac (cartella o singoli file).
    @State private var showMacImporter = false
    @State private var cassettiDalMac = 0
    /// Percorso di un cassetto arrivato dal Mac: serve a verificare che la
    /// password appena scelta sia davvero quella, prima di configurarla.
    @State private var cassettoDalMacDaVerificare: String?
    @State private var verificandoPassword = false
    @StateObject private var sync = LocalSync()
    #endif
    /// Chiave di recupero: si vede solo qui, una volta.
    @State private var recoveryKey = ""
    @State private var recoverySaved = false
    /// Conferma dopo "copia"/"salva su file": senza, il salvataggio andato
    /// a buon fine sembrava non aver fatto niente.
    @State private var recoveryEsito: String?

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 26) {
                header

                Group {
                    switch step {
                    case .intro:     intro
                    case .password:  passwordStep
                    case .recovery:  recoveryStep
                    case .biometry:  biometryStep
                    #if os(iOS)
                    case .mac:       macStep
                    #endif
                    case .importing: importStep
                    case .ready:     ready
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                footer
            }
            #if os(iOS)
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            #else
            .padding(40)
            .frame(width: 520, height: 560)
            #endif
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            IndexLabel(number: step.rawValue + 1, text: title)
            Rectangle().fill(Theme.line).frame(height: 1.2)
        }
    }

    /// Il passo a cui si torna cliccando la freccia — non è sempre
    /// "un rawValue in meno": l'avanzamento salta dei passi (nessun dito,
    /// nessuna importazione da fare), e tornare indietro deve saltarli
    /// allo stesso modo, non fermarsi su uno che non si è mai visto.
    private var passoPrecedente: Step? {
        switch step {
        case .intro:     return nil
        #if os(iOS)
        case .mac:       return .intro
        case .password:  return .mac
        #else
        case .password:  return .intro
        #endif
        case .recovery:  return .password
        case .biometry:  return .recovery
        case .importing: return MasterKey.biometryAvailable ? .biometry : .recovery
        case .ready:
            #if os(iOS)
            if cassettiDalMac > 0 { return MasterKey.biometryAvailable ? .biometry : .recovery }
            #endif
            return .importing
        }
    }

    private var title: String {
        switch step {
        case .intro:     return "benvenuto"
        case .password:  return "la tua unica password"
        case .recovery:  return "la chiave di scorta"
        case .biometry:  return MasterKey.tipoBiometria == .volto ? "sblocco col volto" : "sblocco col dito"
        #if os(iOS)
        case .mac:       return "i cassetti del tuo Mac"
        #endif
        case .importing: return "porta dentro quelle che hai già"
        case .ready:     return "tutto pronto"
        }
    }

    // MARK: - Passi

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("HUSH")
                .font(Theme.display(48))
                .kerning(-1)
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 14) {
                bullet("un caveau, non un servizio",
                       "i tuoi dati restano su questo computer. nessun account, nessun server.")
                bullet("un cassetto per progetto",
                       "ogni progetto ha il suo cassetto, chiuso a chiave per conto suo.")
                bullet("una password per tutto",
                       "una sola chiave apre tutto: quella che scegli adesso.")
                bullet("7 giorni di prova",
                       "poi serve una licenza. quello che hai messo dentro resta tuo: puoi portartelo via quando vuoi.")
            }
        }
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Theme.ink).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(head)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(body)
                    .font(Theme.mono(11))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            #if os(iOS)
            if cassettiDalMac > 0 {
                Text("qui deve essere la stessa password del Mac, altrimenti i cassetti che hai appena importato restano chiusi.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("scegline una lunga e che ricordi. non si può recuperare:\nnon esiste nessuno a cui chiederla.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #else
            Text("scegline una lunga e che ricordi. non si può recuperare:\nnon esiste nessuno a cui chiederla.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            #endif

            HStack(spacing: 8) {
                Group {
                    if reveal {
                        TextField("master password", text: $password)
                    } else {
                        SecureField("master password", text: $password)
                    }
                }
                .textFieldStyle(.plain)
                .font(Theme.mono(13))
                // altezza fissa: SecureField e TextField hanno metriche
                // interne leggermente diverse, senza questo il campo
                // "respira" un pelo quando si passa dall'uno all'altro
                .frame(height: 18)
                .focused($passwordFocused)

                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)

                Button {
                    let generata = PasswordGenerator.generate(.init())
                    password = generata
                    confirm = generata
                    reveal = true
                } label: {
                    Image(systemName: "dice")
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .foregroundStyle(passwordFocused ? Theme.ink : Theme.inkSoft)
                .padding(4)
                .background(passwordFocused ? Theme.yellow.opacity(0.7) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .help("genera una password casuale")
                .overlay(alignment: .top) {
                    if passwordFocused {
                        Text("random")
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
            .animation(.easeOut(duration: 0.15), value: passwordFocused)
            .padding(10)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

            if reveal && !password.isEmpty && password == confirm {
                Text("è casuale: non te la ricorderai. scrivila subito da qualche parte al sicuro, oltre alla chiave di scorta che arriva dopo.")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("ripetila", text: $confirm)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit(advance)

            strengthBar

            if let error {
                Text(error)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
            }
        }
        .onAppear { passwordFocused = true }
    }

    /// Forza: quattro tacche, si riempiono con lunghezza e varietà.
    private var strengthBar: some View {
        let score = strengthScore
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    Rectangle()
                        .fill(i < score ? Theme.ink : Theme.line.opacity(0.25))
                        .frame(height: 4)
                }
            }
            Text(["troppo corta", "debole", "discreta", "buona", "solida"][score])
                .font(Theme.mono(10))
                .foregroundStyle(Theme.inkSoft)
        }
    }

    private var strengthScore: Int {
        var s = 0
        if password.count >= 8 { s += 1 }
        if password.count >= 14 { s += 1 }
        if password.rangeOfCharacter(from: .decimalDigits) != nil
            && password.rangeOfCharacter(from: .letters) != nil { s += 1 }
        if password.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil { s += 1 }
        return min(s, 4)
    }

    /// La chiave di scorta si vede qui e mai più: è cifrata sul disco con sé
    /// stessa, quindi nemmeno l'app può rileggerla.
    private var recoveryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("se dimentichi la master password, questa è l'unica via\nper rientrare. non c'è nessun altro a cui chiederla.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Text(recoveryKey)
                .font(Theme.mono(12, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))

            HStack(spacing: 10) {
                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = recoveryKey
                    #else
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(recoveryKey, forType: .string)
                    #endif
                    recoveryEsito = "copiata negli appunti."
                } label: {
                    Label("copia", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())

                Button { saveRecoveryToFile() } label: {
                    Label("salva su file", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())
            }

            if let recoveryEsito {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 10))
                    Text(recoveryEsito)
                }
                .font(Theme.mono(10, .semibold))
                .foregroundStyle(Theme.ink)
                .transition(.opacity)
            }

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                Text("vale quanto la master password: chi ce l'ha entra. stampala o mettila in cassaforte, non lasciarla sul computer accanto ai vault.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.inkSoft)

        }
    }

    private func saveRecoveryToFile() {
        #if os(iOS)
        // su iPhone niente pannello di salvataggio: la chiave si copia negli
        // appunti e la si incolla dove si vuole (Note, un messaggio a sé...)
        UIPasteboard.general.string = recoveryKey
        recoveryEsito = "copiata negli appunti: incollala dove preferisci."
        #else
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Hush chiave di recupero.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let testo = """
            HUSH. CHIAVE DI RECUPERO

            \(recoveryKey)

            Serve a rientrare se dimentichi la master password.
            Vale quanto la password stessa: chi ce l'ha apre tutto.
            Stampala e conservala lontano dal computer.
            """
            do {
                try testo.write(to: url, atomically: true, encoding: .utf8)
                recoveryEsito = "salvata in «\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)»."
            } catch {
                recoveryEsito = "salvataggio non riuscito: \(error.localizedDescription)"
            }
        }
        #endif
    }

    private var biometryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: MasterKey.tipoBiometria == .volto ? "faceid" : "touchid")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.ink)
            Text(MasterKey.tipoBiometria == .volto
                 ? "puoi aprire Hush guardando lo schermo invece di riscrivere\nla password ogni volta. resta tutto su questo computer:\nla password va nel Portachiavi, protetta dal sensore."
                 : "puoi aprire Hush col dito invece di riscrivere la\npassword ogni volta. resta tutto su questo computer:\nla password va nel Portachiavi, protetta dal sensore.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    #if os(iOS)
    /// La pagina dedicata al Mac: chi scarica l'app sul telefono di solito
    /// ha già Hush sul computer, e i cassetti si portano qui pari pari,
    /// con nomi, icone e post-it.
    private var macStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "desktopcomputer.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.ink)

            if cassettiDalMac > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("\(cassettiDalMac) cassetti arrivati dal Mac")
                        .font(Theme.mono(12, .semibold))
                }
                .foregroundStyle(Theme.ink)
                Text("nomi, icone e post-it compresi. li trovi dentro appena entri.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("l'app del telefono è il compagno di quella sul Mac: per continuare servono i tuoi cassetti. arrivano pari pari, con nomi, icone e post-it — sulla stessa rete WiFi, senza passare da nessun server.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                syncBox

                Text("oppure, a mano")
                    .font(Theme.mono(10, .semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.inkSoft)
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 12) {
                    riga(numero: "1", testo: "sul Mac apri le impostazioni e tocca «esporta i cassetti»")
                    riga(numero: "2", testo: "manda la cartella al telefono con AirDrop: finisce in File")
                    riga(numero: "3", testo: "qui sotto, scegli quella cartella")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "key")
                        .font(.system(size: 11))
                    Text("in tutti e due i casi serve la stessa master password del Mac, o i cassetti non si apriranno.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.mono(10))
                .foregroundStyle(Theme.inkSoft)
            }

            if let error {
                Text(error)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
            }
        }
        .onAppear {
            sync.alCompletamento = { cartella in
                if let importati = try? VaultTransfer.importAll(from: [cartella]), importati > 0 {
                    cassettiDalMac += importati
                    cassettoDalMacDaVerificare = VaultFileManager.shared.projects.last?.path
                }
            }
            if step == .mac { sync.avviaRicerca() }
        }
        .onDisappear { sync.ferma() }
    }

    /// Cerca il Mac sulla stessa rete e mostra lo stato del collegamento:
    /// elenco dei Mac trovati, poi il trasferimento in corso.
    @ViewBuilder
    private var syncBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch sync.stato {
            case .fermo, .inAttesa:
                Button("cerca il Mac sulla rete") { sync.avviaRicerca() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)

            case .inCerca:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(sync.trovati.isEmpty ? "cerco un Mac con Hush aperto sulla stessa rete…" : "trovati:")
                        .font(Theme.mono(11))
                }
                .foregroundStyle(Theme.inkSoft)
                ForEach(sync.trovati, id: \.self) { peer in
                    Button(peer.displayName) { sync.collegati(a: peer) }
                        .buttonStyle(OutlineButtonStyle())
                        .frame(maxWidth: .infinity)
                }

            case .collegato(let nome):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("collegato a \(nome), aspetto i cassetti…")
                        .font(Theme.mono(11))
                }
                .foregroundStyle(Theme.ink)

            case .trasferendo(let fatti, let totale):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("arrivano i cassetti… \(fatti)/\(totale)")
                        .font(Theme.mono(11, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .fatto(let n):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("\(n) cassetti arrivati dal Mac")
                        .font(Theme.mono(12, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .errore(let messaggio):
                Text(messaggio)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
                Button("riprova") { sync.avviaRicerca() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))
    }

    private func riga(numero: String, testo: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(numero)
                .font(Theme.mono(10, .bold))
                .foregroundStyle(Theme.paper)
                .frame(width: 16, height: 16)
                .background(Theme.ink)
            Text(testo)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

    /// Import da un altro gestore. Il CSV è il minimo comun denominatore:
    /// Gli altri gestori di password e i browser esportano tutti un elenco.
    private var importStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.ink)

            Text("se le password ce le hai già da un'altra parte, esporta il file da lì e caricalo qui: finisce tutto in un cassetto solo, che poi puoi riordinare.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if importedCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("\(importedCount) voci pronte da mettere dentro")
                        .font(Theme.mono(12, .semibold))
                }
                .foregroundStyle(Theme.ink)
                .themedImportRow()
            } else {
                Button { showFileImporter = true } label: {
                    Label("scegli il file", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())
            }

            // Promemoria, non errore: in rosso sembrava che qualcosa fosse
            // andato storto ancora prima di toccare qualsiasi cosa.
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11))
                Text("il file esportato contiene le password in chiaro: cancellalo appena finito.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.inkSoft)

            if let error {
                Text(error)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
            }
        }
        #if os(iOS)
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.folder, .data, .commaSeparatedText, .text, .plainText],
                      allowsMultipleSelection: true) { result in
            handleQualunque(result)
        }
        #else
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
            handleCSV(result)
        }
        #endif
        #if os(iOS)
        .fileImporter(isPresented: $showMacImporter,
                      allowedContentTypes: [.folder, .data],
                      allowsMultipleSelection: true) { result in
            handleMacExport(result)
        }
        #endif
    }

    #if os(iOS)
    /// Come il tasto unico del Mac: gli dai qualunque cosa (cassetti,
    /// cartelle esportate, elenchi csv) e capisce lui cosa farne.
    private func handleQualunque(_ result: Result<[URL], Error>) {
        error = nil
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let accessi = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { for (url, ok) in accessi where ok { url.stopAccessingSecurityScopedResource() } }

        var perCassetti: [URL] = []
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "csv", "txt":
                if let entries = try? CSVImport.parse(contentsOf: url) {
                    PendingImport.entries = entries
                    PendingImport.projectName = url.deletingPathExtension().lastPathComponent
                    importedCount = entries.count
                } else {
                    error = "elenco illeggibile."
                }
            default:
                perCassetti.append(url)
            }
        }
        if !perCassetti.isEmpty {
            do {
                let importati = try VaultTransfer.importAll(from: perCassetti)
                cassettiDalMac += importati
                if importati > 0 { cassettoDalMacDaVerificare = VaultFileManager.shared.projects.last?.path }
            } catch {
                self.error = "importazione non riuscita: \(error.localizedDescription)"
            }
        }
    }

    /// Copia dentro al telefono i cassetti esportati dal Mac: stessa
    /// importazione delle impostazioni del Mac, con nomi, icone e colori
    /// presi dall'indice dell'esportazione se c'è.
    private func handleMacExport(_ result: Result<[URL], Error>) {
        error = nil
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        let accessi = urls.map { ($0, $0.startAccessingSecurityScopedResource()) }
        defer { for (url, ok) in accessi where ok { url.stopAccessingSecurityScopedResource() } }
        do {
            cassettiDalMac = try VaultTransfer.importAll(from: urls)
            if cassettiDalMac == 0 {
                error = "lì dentro non ci sono cassetti."
            } else {
                cassettoDalMacDaVerificare = VaultFileManager.shared.projects.last?.path
            }
        } catch {
            self.error = "importazione non riuscita: \(error.localizedDescription)"
        }
    }
    #endif

    private func handleCSV(_ result: Result<URL, Error>) {
        error = nil
        guard case .success(let url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let entries = try CSVImport.parse(contentsOf: url)
            PendingImport.entries = entries
            PendingImport.projectName = url.deletingPathExtension().lastPathComponent
            importedCount = entries.count
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hush è chiuso a chiave.")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
            Text("da qui in poi vedrai la parete dei cassetti: uno per\nprogetto. creane uno col + e mettici dentro la prima\npassword.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Navigazione

    private var trattini: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Rectangle()
                    .fill(s.rawValue <= step.rawValue ? Theme.ink : Theme.line.opacity(0.3))
                    .frame(width: 16, height: 3)
            }
        }
    }

    private var footer: some View {
        // stessa struttura ovunque: i trattini stanno sempre centrati sopra,
        // sotto "indietro" a sinistra e le CTA vere a destra — .fixedSize()
        // toglie ai bottoni la larghezza infinita che il loro stile impone
        // di default, o "indietro" e lo Spacer non avrebbero senso
        VStack(spacing: 16) {
            trattini
                .frame(maxWidth: .infinity, alignment: .center)
            HStack(spacing: 10) {
                if let precedente = passoPrecedente {
                    Button("indietro") {
                        error = nil
                        step = precedente
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .fixedSize()
                }

                Spacer(minLength: 12)

                if step == .biometry {
                    Button("non ora") { step = dopoBiometria }
                        .buttonStyle(OutlineButtonStyle())
                        .fixedSize()
                }
                // il passo .mac non ha "non ora": da lì si può tornare
                // indietro, ma non saltare avanti senza i cassetti del Mac —
                // un telefono senza sarebbe un guscio vuoto con una password
                // diversa da quella vera
                if step == .importing && importedCount == 0 {
                    Button("salta") { step = .ready }
                        .buttonStyle(OutlineButtonStyle())
                        .fixedSize()
                }

                Button(primaryLabel) { advance() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .fixedSize()
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.4)
            }
        }
        // niente animazione implicita quando "non ora" compare/sparisce:
        // altrimenti il bottone accanto sembra scivolare al suo posto
        .transaction { $0.animation = nil }
    }

    private var primaryLabel: String {
        switch step {
        case .intro:     return "comincia"
        case .password:
            #if os(iOS)
            if verificandoPassword { return "verifico…" }
            #endif
            return "imposta"
        case .recovery:  return "fatto"
        case .biometry:  return "attiva"
        #if os(iOS)
        case .mac:       return cassettiDalMac > 0 ? "avanti" : "scegli la cartella"
        #endif
        case .importing: return importedCount > 0 ? "avanti" : "scegli file"
        case .ready:     return "entra"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .password:
            #if os(iOS)
            guard !verificandoPassword else { return false }
            #endif
            return password.count >= 8 && password == confirm
        default:
            return true
        }
    }

    private func advance() {
        error = nil
        switch step {
        case .intro:
            #if os(iOS)
            step = .mac
            #else
            step = .password
            #endif

        #if os(iOS)
        case .mac:
            // fatta l'importazione dal Mac si salta la pagina più avanti che
            // chiede lo stesso csv/elenco: serve solo a chi parte da zero
            if cassettiDalMac > 0 { step = .password } else { showMacImporter = true }
        #endif

        case .password:
            guard password.count >= 8 else {
                error = "almeno 8 caratteri."
                return
            }
            guard password == confirm else {
                error = "le due password non combaciano."
                return
            }
            #if os(iOS)
            if let percorso = cassettoDalMacDaVerificare {
                verificaPasswordDelMac(percorso)
                return
            }
            #endif
            configuraMasterPassword()

        case .recovery:
            step = MasterKey.biometryAvailable ? .biometry : dopoBiometria

        case .biometry:
            do {
                try MasterKey.enableBiometry(password: password)
                step = dopoBiometria
            } catch {
                self.error = "non è stato possibile attivarlo: \(error.localizedDescription)"
            }

        case .importing:
            if importedCount > 0 { step = .ready } else { showFileImporter = true }

        case .ready:
            password = ""; confirm = ""
            onDone()
        }
    }

    /// Dopo password/scorta/biometria: se sul Mac c'erano già cassetti,
    /// quelli sono arrivati subito dopo il benvenuto e non serve chiedere
    /// di nuovo un elenco da importare.
    private var dopoBiometria: Step {
        #if os(iOS)
        cassettiDalMac > 0 ? .ready : .importing
        #else
        .importing
        #endif
    }

    private func configuraMasterPassword() {
        MasterKey.configure(password: password)
        // la chiave di scorta nasce subito: dopo, senza la master
        // password in mano, non si potrebbe più cifrarci dentro niente
        recoveryKey = (try? RecoveryKit.create(masterPassword: password)) ?? ""
        step = .recovery
    }

    #if os(iOS)
    /// Prima di adottare la password come master password di Hush, la si
    /// prova su un cassetto arrivato dal Mac: se non lo apre, quei cassetti
    /// resterebbero chiusi per sempre, ed è meglio dirlo subito che dopo.
    private func verificaPasswordDelMac(_ percorso: String) {
        verificandoPassword = true
        let pwd = password
        Task.detached(priority: .userInitiated) {
            let corrisponde: Bool
            if let bytes = try? Data(contentsOf: URL(fileURLWithPath: percorso)),
               (try? Kdbx4.open(data: Array(bytes), password: pwd)) != nil {
                corrisponde = true
            } else {
                corrisponde = false
            }
            await MainActor.run {
                verificandoPassword = false
                if corrisponde {
                    configuraMasterPassword()
                } else {
                    error = "non è la password del Mac: i cassetti che hai importato non si aprirebbero. riscrivila uguale a quella di là."
                }
            }
        }
    }
    #endif
}
