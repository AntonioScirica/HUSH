import SwiftUI
import UniformTypeIdentifiers
import VaultCore
#if os(macOS)
import AppKit
#else
import UIKit
import AuthenticationServices
#endif

/// I corpi del Mac (10-11 pt) sul telefono sono illeggibili: stessa scala,
/// tre punti in più, solo per i testi dell'onboarding.
func carattereOnboarding(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    #if os(iOS)
    Theme.mono(size + 3, weight)
    #else
    Theme.mono(size, weight)
    #endif
}


/// Primo avvio: si presenta Hush, si sceglie la master password e —
/// se la macchina ce l'ha — si attiva il dito. Stessa carta, stesso
/// inchiostro, stessi divider numerati del resto dell'app.
struct OnboardingView: View {
    /// Vero finché lo splash sta ancora animando il suo "HUSH" verso questa
    /// posizione: qui il titolo resta invisibile (ma misurato), e compare
    /// solo quando la scritta dello splash gli è atterrata sopra.
    var titoloNascosto: Bool = false
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        #if os(iOS)
        // sul telefono il collegamento col Mac viene subito dopo il
        // benvenuto: chi scarica l'app di solito ha già i cassetti di là,
        // e la password che imposta tra un attimo dovrà essere la stessa
        // usata sul Mac — non ha senso chiederla prima di dirlo.
        case intro, mac, password, recovery, biometry, autofill, importing, ready
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
    /// Vera solo appena generata dal dado: un edit manuale la spegne, o
    /// l'avviso "non te la ricorderai" resterebbe attaccato a una password
    /// scritta a mano solo perché coincide per lunghezza/contenuto.
    @State private var passwordGenerata = false

    @State private var showFileImporter = false
    #if os(macOS)
    /// Sul Mac l'import qui usa lo stesso meccanismo delle Impostazioni
    /// (VaultTransfer.chooseImport + anteprima): il vecchio .fileImporter
    /// accettava solo .csv, .1pux e tutto il resto restavano fuori.
    private struct ImportJob: Identifiable {
        let id = UUID()
        let previews: [VaultTransfer.Preview]
    }
    @State private var importJob: ImportJob?
    @State private var leggendo = false
    @State private var importando = false
    #endif
    @State private var importedCount = 0
    #if os(iOS)
    @State private var cassettiDalMac = 0
    /// Chi non ha un Mac (o non vuole aspettarlo) può creare il vault
    /// direttamente qui — Apple ha rifiutato l'app (Guideline 5.6) perché
    /// senza questa via il reviewer restava bloccato per sempre alla
    /// ricerca del Mac, un pattern che il loro sistema legge come
    /// funzionalità nascosta: non è più "o Mac o niente".
    @State private var creaSenzaMac = false
    /// Se il permesso "Rete locale" è negato, la ricerca resta in silenzio
    /// per sempre — niente errore, niente peer, un'attesa che non finisce
    /// mai. Passato un po' di tempo senza trovare nessuno si offre
    /// comunque la via delle Impostazioni, permesso negato o no.
    @State private var ricercaLenta = false
    @State private var ricercaTask: Task<Void, Never>?
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

            if step == .ready {
                readyPage
            } else {
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
                        case .autofill:  autofillStep
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
        }
        .preferredColorScheme(.light)
    }

    private var readyBodyText: String {
        #if os(iOS)
        cassettiDalMac > 0
            ? "Da ora in poi i tuoi dati sono al sicuro qui dentro. Trovi già i progetti arrivati dal Mac: toccane uno per vedere le password."
            : "Da ora in poi i tuoi dati sono al sicuro qui dentro. Crea il primo progetto col + e mettici dentro la prima password."
        #else
        "Da ora in poi i tuoi dati sono al sicuro qui dentro. Vedrai la parete dei cassetti: uno per progetto. Creane uno col + e mettici dentro la prima password."
        #endif
    }

    /// Ultimo passo: niente testata, niente frecce, niente trattini —
    /// non si torna indietro da qui, resta solo entrare.
    private var readyPage: some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Hush è chiuso a chiave.")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
            Text(readyBodyText)
                .font(carattereOnboarding(11))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Button("Entra") { advance() }
                .buttonStyle(InkButtonStyle(prominent: true))
                .fixedSize()
                .padding(.top, 24)
            Spacer()
        }
        #if os(iOS)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .padding(40)
        .frame(width: 520, height: 560)
        #endif
    }

    // MARK: - Testata

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                if let precedente = passoPrecedente {
                    Button {
                        error = nil
                        step = precedente
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkSoft)
                }
                IndexLabel(number: step.rawValue + 1, text: title)
            }
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
        #if os(iOS)
        case .autofill:  return MasterKey.biometryAvailable ? .biometry : .recovery
        case .importing: return .autofill
        case .ready:
            if cassettiDalMac > 0 { return .autofill }
            return .importing
        #else
        case .importing: return MasterKey.biometryAvailable ? .biometry : .recovery
        case .ready:     return .importing
        #endif
        }
    }

    private var title: String {
        switch step {
        case .intro:     return "Benvenuto"
        case .password:  return "La tua unica password"
        case .recovery:  return "La chiave di scorta"
        case .biometry:  return MasterKey.tipoBiometria == .volto ? "Sblocco col volto" : "Sblocco col dito"
        #if os(iOS)
        case .mac:       return "I cassetti del tuo Mac"
        case .autofill:  return "Riempi i login da solo"
        #endif
        case .importing: return "Porta dentro quelle che hai già"
        case .ready:     return "Tutto pronto"
        }
    }

    // MARK: - Passi

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("HUSH")
                .font(Theme.display(48))
                .kerning(-1)
                .foregroundStyle(Theme.ink)
                .opacity(titoloNascosto ? 0 : 1)
                .background(GeometryReader { g in
                    Color.clear.preference(key: HushTitleFrameKey.self, value: g.frame(in: .global))
                })

            VStack(alignment: .leading, spacing: 14) {
                bullet("Un caveau, non un servizio",
                       "I tuoi dati restano su questo computer. Nessun account, nessun server.")
                bullet("Ogni progetto nel suo cassetto",
                       "Tutto organizzato in cassetti, ognuno racchiude i dati di un progetto.")
                bullet("Una chiave per aprirle tutte",
                       "Una sola password sblocca tutti i cassetti.")
                bullet("Gratis e open source",
                       "Niente prova, niente licenza. Quello che ci metti dentro resta tuo: puoi portartelo via quando vuoi.")
            }
        }
    }

    private func bullet(_ head: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Rectangle().fill(Theme.ink).frame(width: 7, height: 7).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(head)
                    .font(carattereOnboarding(12, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(body)
                    .font(carattereOnboarding(11))
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
                Text("Qui deve essere la stessa password del Mac, altrimenti i cassetti che hai appena importato restano chiusi.")
                    .font(carattereOnboarding(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Scegline una lunga e che ricordi. Non si può recuperare:\nnon esiste nessuno a cui chiederla.")
                    .font(carattereOnboarding(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #else
            Text("Scegline una lunga e che ricordi. Non si può recuperare:\nnon esiste nessuno a cui chiederla.")
                .font(carattereOnboarding(11))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            #endif

            HStack(spacing: 8) {
                Group {
                    if reveal {
                        TextField("Master password", text: $password)
                    } else {
                        SecureField("Master password", text: $password)
                    }
                }
                .textFieldStyle(.plain)
                .font(carattereOnboarding(13))
                .focused($passwordFocused)
                .onChange(of: password) { _, _ in
                    if passwordFocused { passwordGenerata = false }
                }

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
                    passwordGenerata = true
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
                        Text("Random")
                            .font(carattereOnboarding(9, .semibold))
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
            .frame(height: Theme.fieldHeight)
            .padding(.horizontal, 10)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))

            if passwordGenerata && !password.isEmpty {
                Text("È casuale: non te la ricorderai. Scrivila subito da qualche parte al sicuro, oltre alla chiave di scorta che arriva dopo.")
                    .font(carattereOnboarding(10))
                    .foregroundStyle(Theme.danger)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("Ripetila", text: $confirm)
                .textFieldStyle(PaperFieldStyle())
                .onSubmit(advance)
                .onChange(of: confirm) { _, _ in passwordGenerata = false }

            strengthBar

            if let error {
                Text(error)
                    .font(carattereOnboarding(11))
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
            Text(["Troppo corta", "Debole", "Discreta", "Buona", "Solida"][score])
                .font(carattereOnboarding(10))
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
            Text("Se dimentichi la master password, questa è l'unica via\nper rientrare. Non c'è nessun altro a cui chiederla.")
                .font(carattereOnboarding(11))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(recoveryKey)
                .font(carattereOnboarding(12, .semibold))
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
                    recoveryEsito = "Copiata negli appunti."
                } label: {
                    Label("Copia", systemImage: "doc.on.doc").frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())

                Button { saveRecoveryToFile() } label: {
                    Label("Salva file", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButtonStyle())
            }

            if let recoveryEsito {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark").font(.system(size: 10))
                    Text(recoveryEsito)
                }
                .font(carattereOnboarding(10, .semibold))
                .foregroundStyle(Theme.ink)
                .transition(.opacity)
            }

            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                Text("Vale quanto la master password: chi ce l'ha entra. Stampala o mettila in cassaforte, non lasciarla sul computer accanto ai vault.")
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(carattereOnboarding(10))
            .foregroundStyle(Theme.inkSoft)

        }
    }

    private func saveRecoveryToFile() {
        #if os(iOS)
        // su iPhone niente pannello di salvataggio: la chiave si copia negli
        // appunti e la si incolla dove si vuole (Note, un messaggio a sé...)
        UIPasteboard.general.string = recoveryKey
        recoveryEsito = "Copiata negli appunti: incollala dove preferisci."
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
                recoveryEsito = "Salvata in «\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)»."
            } catch {
                recoveryEsito = "Salvataggio non riuscito: \(error.localizedDescription)"
            }
        }
        #endif
    }

    private var biometryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: MasterKey.tipoBiometria == .volto ? "faceid" : "touchid")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 130)
                .background(Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))
            Text(MasterKey.tipoBiometria == .volto
                 ? "Puoi aprire Hush guardando lo schermo invece di riscrivere la password ogni volta. Resta tutto su questo computer: solo tu, col tuo volto, puoi farla uscire dal Portachiavi. Ogni tanto te la richiederà comunque, così non rischi di dimenticarla."
                 : "Puoi aprire Hush col dito invece di riscrivere la password ogni volta. Resta tutto su questo computer: solo tu, col tuo dito, puoi farla uscire dal Portachiavi. Ogni tanto te la richiederà comunque, così non rischi di dimenticarla.")
                .font(carattereOnboarding(11))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let error {
                Text(error)
                    .font(carattereOnboarding(11))
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
                        .font(carattereOnboarding(12, .semibold))
                }
                .foregroundStyle(Theme.ink)
                Text("Nomi, icone e post-it compresi. Li trovi dentro appena entri.")
                    .font(carattereOnboarding(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else if creaSenzaMac {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("Si parte da qui")
                        .font(carattereOnboarding(12, .semibold))
                }
                .foregroundStyle(Theme.ink)
                Text("Crei il vault direttamente sul telefono. Potrai abbinare un Mac quando vuoi, dalle Impostazioni.")
                    .font(carattereOnboarding(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Torna alla ricerca del Mac") { creaSenzaMac = false }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)
            } else {
                Text("L'app del telefono è il compagno di quella sul Mac: se ne hai uno con Hush aperto, i cassetti arrivano pari pari, con nomi, icone e post-it — sulla stessa rete WiFi, senza passare da nessun server. Se non lo hai, puoi anche partire direttamente da qui.")
                    .font(carattereOnboarding(11))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                syncBox
            }

            if let error {
                Text(error)
                    .font(carattereOnboarding(11))
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
            if step == .mac { avviaRicercaConTimeout() }
        }
        .onDisappear {
            sync.ferma()
            ricercaTask?.cancel()
            ricercaLenta = false
        }
        .onChange(of: sync.trovati.isEmpty) { _, vuoto in
            if !vuoto { ricercaLenta = false }
        }
    }

    private func avviaRicercaConTimeout() {
        ricercaLenta = false
        sync.avviaRicerca()
        ricercaTask?.cancel()
        ricercaTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            ricercaLenta = true
        }
    }

    /// Spiega come accendere il riempimento automatico di sistema: senza
    /// questo giro nelle impostazioni di iOS, Safari non proporrà mai le
    /// voci di Hush sopra la tastiera — e non è una cosa che si indovina.
    private var autofillStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "rectangle.and.pencil.and.ellipsis")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.ink)

            Text("Safari e le altre app possono riempire i login da soli, con le voci di Hush proposte sopra la tastiera. Va acceso una volta:")
                .font(carattereOnboarding(11))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // niente istruzioni a memoria su dove stia la voce (cambia posto
            // a ogni versione di iOS): questo bottone apre la schermata
            // giusta direttamente, è un'API fatta apposta per i password manager
            Button("Apri le impostazioni e attiva Hush") {
                ASSettingsHelper.openCredentialProviderAppSettings()
            }
            .buttonStyle(OutlineButtonStyle())
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                riga(numero: "1", testo: "Tocca il bottone qui sopra")
                riga(numero: "2", testo: "Attiva «Hush» nell'elenco")
                riga(numero: "3", testo: "Torna qui e vai avanti")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                Text("I suggerimenti compaiono per le voci che hanno un indirizzo salvato (es. netflix.com): è così che iOS capisce su quale sito proporle.")
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(carattereOnboarding(10))
            .foregroundStyle(Theme.inkSoft)
        }
    }

    /// Cerca il Mac sulla stessa rete e mostra lo stato del collegamento:
    /// elenco dei Mac trovati, poi il trasferimento in corso.
    @ViewBuilder
    private var syncBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch sync.stato {
            case .fermo, .inAttesa:
                Button("Cerca il Mac sulla rete") { avviaRicercaConTimeout() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)

            case .inCerca:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(sync.trovati.isEmpty ? "Cerco un Mac con Hush aperto sulla stessa rete…" : "Trovati:")
                        .font(carattereOnboarding(11))
                }
                .foregroundStyle(Theme.inkSoft)
                ForEach(sync.trovati, id: \.self) { peer in
                    Button(peer.displayName) { sync.collegati(a: peer) }
                        .buttonStyle(OutlineButtonStyle())
                        .frame(maxWidth: .infinity)
                }

                // Il permesso "Rete locale" negato non dà nessun errore:
                // la ricerca resta muta per sempre, indistinguibile da "il
                // Mac è spento". Passato un po', si offre comunque la via
                // delle Impostazioni — permesso negato o no, non fa male.
                if ricercaLenta && sync.trovati.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Non lo trovo. Se hai risposto «no» al permesso di trovare i dispositivi in rete, va riacceso a mano:")
                            .font(carattereOnboarding(10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Apri le impostazioni") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                        .buttonStyle(OutlineButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 4)
                }

            case .collegato(let nome):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Collegato a \(nome), aspetto i cassetti…")
                        .font(carattereOnboarding(11))
                }
                .foregroundStyle(Theme.ink)
                // Sul Mac compare un conferma/rifiuta che va toccato lì:
                // senza dirlo esplicitamente sembra che il telefono sia
                // bloccato, mentre in realtà aspetta un tap sull'altro schermo.
                Text("Guarda il Mac: deve confermare la richiesta lì prima di mandare i cassetti.")
                    .font(carattereOnboarding(10))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

            case .trasferendo(let fatti, let totale):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Arrivano i cassetti… \(fatti)/\(totale)")
                        .font(carattereOnboarding(11, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .fatto(let n):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("\(n) cassetti arrivati dal Mac")
                        .font(carattereOnboarding(12, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .errore(let messaggio):
                Text(messaggio)
                    .font(carattereOnboarding(11))
                    .foregroundStyle(Theme.danger)
                Button("Riprova") { sync.avviaRicerca() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)
            }

            // Via d'uscita per chi non ha un Mac (o non vuole abbinarlo
            // ora): niente più vicolo cieco. Non compare a collegamento
            // già in corso o riuscito, per non confondere.
            if !creaSenzaMac, case .collegato = sync.stato {} else if !creaSenzaMac {
                Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1).padding(.vertical, 6)
                Button("Continua senza Mac") {
                    sync.ferma()
                    creaSenzaMac = true
                }
                .buttonStyle(OutlineButtonStyle())
                .frame(maxWidth: .infinity)
                Text("Puoi comunque abbinare un Mac più avanti dalle Impostazioni.")
                    .font(carattereOnboarding(9))
                    .foregroundStyle(Theme.inkSoft)
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
                .font(carattereOnboarding(10, .bold))
                .foregroundStyle(Theme.paper)
                .frame(width: 16, height: 16)
                .background(Theme.ink)
            Text(testo)
                .font(carattereOnboarding(11))
                .foregroundStyle(Theme.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    #endif

    /// Import da un altro gestore. Il CSV è il minimo comun denominatore:
    /// Gli altri gestori di password e i browser esportano tutti un elenco.
    /// Da dove possono arrivare le password: schede informative, per far
    /// capire a colpo d'occhio che qualunque cosa si abbia già va bene.
    /// Una riga intera è il bottone: ci clicchi sopra e parte l'azione,
    /// non serve una CTA a parte più sotto.
    private func fonteImport(icona: String, titolo: String, testo: String, azione: @escaping () -> Void) -> some View {
        Button(action: azione) {
            HStack(spacing: 14) {
                Image(systemName: icona)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titolo)
                        .font(carattereOnboarding(12, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(testo)
                        .font(carattereOnboarding(10))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1.1))
        }
        .buttonStyle(.plain)
    }

    private var importStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Se le password ce le hai già da un'altra parte, esporta il file da lì e caricalo qui: ogni fonte finisce nel suo cassetto, che poi puoi riordinare con calma.")
                .font(carattereOnboarding(11))
                .lineSpacing(3)
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            // ultima pagina prima della fine: si prende tutto lo spazio.
            // Quattro righe, tutte cliccabili: le prime tre aprono il
            // file, l'ultima è la via d'uscita per chi non ha niente da
            // portare — così il piede qui sotto resta senza CTA doppie.
            VStack(spacing: 10) {
                fonteImport(icona: "lock.rectangle.stack",
                            titolo: "Un altro gestore",
                            testo: "Porta dentro Hush tutto quello che hai in un altro programma per le password.") {
                    avviaImportazione()
                }
                fonteImport(icona: "globe",
                            titolo: "Il browser",
                            testo: "Porta dentro Hush le password salvate nel browser.") {
                    avviaImportazione()
                }
                fonteImport(icona: "doc.text",
                            titolo: "Un elenco",
                            testo: "Un file csv qualunque, anche scritto a mano: titolo, utente, password.") {
                    avviaImportazione()
                }
                fonteImport(icona: "arrow.uturn.left",
                            titolo: "Niente, per ora",
                            testo: "Si può sempre fare più avanti, dalle impostazioni.") {
                    step = .ready
                }
            }
            #if os(macOS)
            if leggendo {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Leggo…")
                        .font(carattereOnboarding(11))
                }
                .foregroundStyle(Theme.inkSoft)
            }
            #endif

            if importedCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                    Text("\(importedCount) voci pronte da mettere dentro")
                        .font(carattereOnboarding(13, .semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.yellow.opacity(0.35))
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
            }

            if let error {
                Text(error)
                    .font(carattereOnboarding(11))
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
        .sheet(item: $importJob) { job in
            ImportPreviewView(previews: job.previews) { scelti in
                importJob = nil
                importando = true
                let voci = scelti.reduce(0) { $0 + $1.entries.count }
                Task {
                    do {
                        let n = try await VaultTransfer.importChosenAsync(scelti)
                        importedCount += voci
                        _ = n
                    } catch {
                        self.error = "Importazione non riuscita: \(error.localizedDescription)"
                    }
                    importando = false
                }
            } onCancel: {
                importJob = nil
            }
            .background(Theme.paper.ignoresSafeArea())
            .preferredColorScheme(.light)
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
                    error = "Elenco illeggibile."
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
                self.error = "Importazione non riuscita: \(error.localizedDescription)"
            }
        }
    }

    #endif

    /// Punto d'ingresso unico delle tre righe: sul Mac apre lo stesso
    /// pannello "scegli qualunque cosa" delle Impostazioni, sul telefono
    /// il file importer di sistema.
    private func avviaImportazione() {
        #if os(macOS)
        VaultTransfer.chooseImport { urls in
            guard !urls.isEmpty else { return }
            let chiave = MasterKey.session
            leggendo = true
            error = nil
            Task {
                let previews = await VaultTransfer.inspectAny(urls, key: chiave)
                leggendo = false
                importJob = ImportJob(previews: previews)
            }
        }
        #else
        showFileImporter = true
        #endif
    }


    private var ready: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hush è chiuso a chiave.")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
            Text("Da qui in poi vedrai la parete dei cassetti: uno per\nprogetto. Creane uno col + e mettici dentro la prima\npassword.")
                .font(carattereOnboarding(11))
                .foregroundStyle(Theme.inkSoft)
                .lineSpacing(3)
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
        // trattini sempre centrati sopra; sotto, le CTA centrate insieme —
        // "indietro" non c'è più qui, è la freccina accanto al numero del
        // passo, in testata
        VStack(spacing: 24) {
            trattini
                .frame(maxWidth: .infinity, alignment: .center)
            // sul passo dell'import, senza niente importato, le quattro
            // righe qui sopra sono già l'azione: nessuna CTA doppia sotto
            if !(step == .importing && importedCount == 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if step == .biometry {
                    Button("Non ora") { step = dopoBiometria }
                        .buttonStyle(OutlineButtonStyle())
                        .fixedSize()
                }
                // il passo .mac non ha "non ora": da lì si può tornare
                // indietro, ma non saltare avanti senza i cassetti del Mac —
                // un telefono senza sarebbe un guscio vuoto con una password
                // diversa da quella vera

                Button(primaryLabel) { advance() }
                    .buttonStyle(InkButtonStyle(prominent: true))
                    .fixedSize()
                    .disabled(!canAdvance)
                    .opacity(canAdvance ? 1 : 0.4)

                Spacer(minLength: 0)
            }
            }
        }
        // niente animazione implicita quando "non ora" compare/sparisce:
        // altrimenti il bottone accanto sembra scivolare al suo posto
        .transaction { $0.animation = nil }
    }

    private var primaryLabel: String {
        switch step {
        case .intro:     return "Comincia"
        case .password:
            #if os(iOS)
            if verificandoPassword { return "Verifico…" }
            #endif
            return "Imposta"
        case .recovery:  return "Fatto"
        case .biometry:  return "Attiva"
        #if os(iOS)
        case .mac:       return "Avanti"
        case .autofill:  return "Avanti"
        #endif
        case .importing: return importedCount > 0 ? "Avanti" : "Scegli file"
        case .ready:     return "Entra"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .password:
            #if os(iOS)
            guard !verificandoPassword else { return false }
            #endif
            return password.count >= 8 && password == confirm
        #if os(iOS)
        case .mac: return cassettiDalMac > 0 || creaSenzaMac
        #endif
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
            // arrivati qui canAdvance è già vero solo se cassettiDalMac > 0:
            // fatta l'importazione si salta la pagina più avanti che
            // chiede lo stesso csv/elenco, serve solo a chi parte da zero
            step = .password
        #endif

        case .password:
            guard password.count >= 8 else {
                error = "Almeno 8 caratteri."
                return
            }
            guard password == confirm else {
                error = "Le due password non combaciano."
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
            MasterKey.enableBiometry(password: password) { esito in
                switch esito {
                case .success:
                    step = dopoBiometria
                case .failure(let error):
                    self.error = "Non è stato possibile attivarlo: \(error.localizedDescription)"
                }
            }

        #if os(iOS)
        case .autofill:
            step = cassettiDalMac > 0 ? .ready : .importing
        #endif

        case .importing:
            // il bottone "Avanti" qui compare solo a importazione già
            // fatta: le quattro righe sopra coprono l'altro caso
            step = .ready

        case .ready:
            password = ""; confirm = ""
            onDone()
        }
    }

    /// Dopo password/scorta/biometria: sul telefono prima si spiega come
    /// accendere il riempimento automatico (il passo che segue), poi — se
    /// sul Mac c'erano già cassetti — si è pronti, senza richiedere un
    /// elenco da importare.
    private var dopoBiometria: Step {
        #if os(iOS)
        .autofill
        #else
        .importing
        #endif
    }

    private func configuraMasterPassword() {
        MasterKey.configure(password: password)
        #if os(iOS)
        // I cassetti arrivati dal Mac hanno già la LORO chiave di scorta,
        // creata là: mostrarne qui una seconda (diversa, di questo device)
        // confonderebbe soltanto — quale delle due conta, in caso di guai?
        if cassettiDalMac > 0 {
            step = MasterKey.biometryAvailable ? .biometry : dopoBiometria
            return
        }
        #endif
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
                    error = "Non è la password del Mac: i cassetti che hai importato non si aprirebbero. Riscrivila uguale a quella di là."
                }
            }
        }
    }
    #endif
}
