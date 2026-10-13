import SwiftUI
#if os(macOS)
import AppKit
import SafariServices
import ServiceManagement
#else
import UIKit
#endif
import UniformTypeIdentifiers

/// Impostazioni delHush: chiave d'accesso, cosa scade da solo e come
/// nascono le password. Poche voci, tutte con una conseguenza concreta.
struct SettingsView: View {
    let onClose: () -> Void
    /// Voci lette da un .csv e pronte da mettere in un cassetto: le sistema
    /// la home, che è l'unica a sapere come si crea un progetto.
    var onImport: () -> Void = {}

    @State private var biometry = MasterKey.biometryEnabled
    @State private var autolock = Preferences.autolockMinutes
    @State private var clipboard = Preferences.clipboardSeconds
    @State private var length = Preferences.passwordLength
    @State private var typeAgain = Preferences.typeAgainDays
    @State private var vistaClassica = Preferences.vistaClassica
    @State private var showImporter = false
    @State private var error: String?
    @State private var note: String?
    /// Chiave appena generata: mostrata finché la finestra resta aperta.
    @State private var newRecovery: String?
    @State private var confirmRegenerate = false
    @State private var licenseText = ""
    @State private var confirmDetach = false
    /// I dati viaggiano CON la presentazione, non in uno stato letto a parte:
    /// assegnare l'elenco e alzare un flag nello stesso istante faceva
    /// costruire la sheet con lo stato di prima, cioè vuota, la prima volta.
    private struct ImportJob: Identifiable {
        let id = UUID()
        let previews: [VaultTransfer.Preview]
    }
    @State private var importJob: ImportJob?
    @State private var leggendo = false
    @State private var importando = false
    #if os(macOS)
    /// Il pannello di consenso OAuth su Google è ancora in "Testing": solo
    /// gli utenti di test aggiunti a mano possono collegarsi, e i token
    /// scadono ogni 7 giorni — inutile mostrarla finché non è pubblicata.
    static let mostraBackupDrive = false
    @State private var estensioneSafariAttiva = false
    @State private var erroreSafariManuale = false
    @State private var tokenChromeCopiato = false
    @State private var driveConnesso = GoogleDriveAuth.shared.isConnected
    @State private var driveBackupInCorso = false
    @State private var driveErrore: String?
    @State private var avviaAlLogin = SMAppService.mainApp.status == .enabled
    @State private var mostraDock = Preferences.mostraDock
    @State private var scorciatoiaRapida = Preferences.quickAddHotKey
    @State private var scorciatoiaRicerca = Preferences.searchHotKey
    #endif

    /// Stessa istanza di RootView (Mac) e del sync bidirezionale (iPhone).
    @ObservedObject private var sync = LocalSync.shared

    /// "2.1 (13)": versione più il numero di build, per capire al volo se
    /// quella installata è davvero l'ultima uscita.
    private var versione: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "Hush \(v) (\(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                IndexLabel(text: "Impostazioni")
                Rectangle().fill(Theme.line).frame(height: 1.2)
            }
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Solo Mac: la licenza si compra e si attiva lì. Il
                    // telefono non funziona da solo comunque (l'onboarding
                    // pretende i cassetti del Mac), quindi non ha un suo
                    // conto alla rovescia — vedi RootView.
                    section("Licenza")

                    if let info = License.active {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                            Text("Attiva · \(info.email)")
                                .font(Theme.mono(11, .semibold))
                        }
                        .foregroundStyle(Theme.ink)

                        Text("Vale per un dispositivo. Per spostarla su un altro staccala da qui, poi esporta i cassetti e riattivala di là.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        Button { confirmDetach = true } label: {
                            Label("Stacca da questo dispositivo", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                    } else {
                        Text(License.trialDaysLeft > 0
                             ? "Prova: mancano \(License.trialDaysLeft) giorni."
                             : "La prova è finita: inserisci la licenza per continuare.")
                            .font(Theme.mono(10))
                            .foregroundStyle(License.trialDaysLeft > 0 ? Theme.inkSoft : Theme.danger)

                        // Dirlo prima, non quando succede: chi affida le
                        // proprie password a un programma ha diritto di
                        // sapere in partenza cosa gli resta in mano.
                        Text("Passati i 7 giorni Hush si blocca: i cassetti non si aprono più da qui finché non attivi la licenza.\n\nquello che ci hai messo dentro resta comunque tuo: dalla schermata di blocco puoi sempre portartelo via, e lo riapri anche senza Hush.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("Incolla qui la licenza", text: $licenseText, axis: .vertical)
                            .textFieldStyle(PaperFieldStyle())
                            .lineLimit(1...4)

                        Button {
                            if License.register(licenseText) != nil {
                                licenseText = ""; note = "Licenza attivata."; error = nil
                            } else {
                                error = "Questa licenza non è valida."
                            }
                        } label: {
                            Label("Attiva", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(licenseText.isEmpty)
                    }

                    divider
                    section("Chiave d'accesso")

                    if MasterKey.biometryAvailable {
                        row(MasterKey.tipoBiometria == .volto ? "Sblocco col volto" : "Sblocco col dito",
                            "Apre Hush col sensore invece della password.") {
                            Toggle("", isOn: $biometry)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .onChange(of: biometry) { _, on in applyBiometry(on) }
                        }
                    }

                    row("Riscrivi la password ogni",
                        MasterKey.tipoBiometria == .volto
                        ? "Ogni tanto te la richiede comunque, anche col volto attivo: così non la dimentichi."
                        : "Ogni tanto te la richiede comunque, anche col dito attivo: così non la dimentichi.") {
                        Picker("", selection: $typeAgain) {
                            Text("3 giorni").tag(3)
                            Text("7 giorni").tag(7)
                            Text("14 giorni").tag(14)
                            Text("30 giorni").tag(30)
                            Text("Mai").tag(0)
                        }
                        .labelsHidden()
                        .onChange(of: typeAgain) { _, v in Preferences.typeAgainDays = v }
                    }

                    Text(reminderText)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)

                    #if os(macOS)
                    divider
                    section("Aspetto")

                    row("Vista a elenco",
                        "La schermata classica con la barra laterale, al posto della parete di cassetti.") {
                        Toggle("", isOn: $vistaClassica)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: vistaClassica) { _, on in
                                Preferences.vistaClassica = on
                            }
                    }

                    row("Avvia al login",
                        "Hush parte da sé nella menu bar: l'estensione funziona subito, senza doverlo riaprire ogni volta.") {
                        Toggle("", isOn: $avviaAlLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: avviaAlLogin) { _, on in
                                try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                            }
                    }

                    row("Mostra nel Dock",
                        "Spegnilo se ti basta l'icona nella menu bar: niente più icona nel Dock.") {
                        Toggle("", isOn: $mostraDock)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: mostraDock) { _, on in
                                Preferences.mostraDock = on
                                NSApp.setActivationPolicy(on ? .regular : .accessory)
                            }
                    }

                    divider
                    section("Scorciatoie")

                    row("Aggiungi voce", "Apre il popup rapido per una nuova password, da qualunque app.") {
                        HotKeyRecorder(combo: $scorciatoiaRapida) {
                            Preferences.quickAddHotKey = scorciatoiaRapida
                            NotificationCenter.default.post(name: .scorciatoieHushCambiate, object: nil)
                        }
                        .frame(width: 180)
                    }

                    row("Cerca password", "Apre il popup di ricerca, per copiare una password senza aprire Hush.") {
                        HotKeyRecorder(combo: $scorciatoiaRicerca) {
                            Preferences.searchHotKey = scorciatoiaRicerca
                            NotificationCenter.default.post(name: .scorciatoieHushCambiate, object: nil)
                        }
                        .frame(width: 180)
                    }
                    #endif

                    divider
                    section("Da sé")

                    row("Richiudi dopo",
                        "Hush si blocca da solo se lo lasci lì aperto.") {
                        Picker("", selection: $autolock) {
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("Mai").tag(0)
                        }
                        .labelsHidden()
                        .onChange(of: autolock) { _, v in Preferences.autolockMinutes = v }
                    }

                    row("Svuota gli appunti dopo",
                        "Cancella la password copiata, così non resta lì in giro.") {
                        Picker("", selection: $clipboard) {
                            Text("15 s").tag(15)
                            Text("30 s").tag(30)
                            Text("60 s").tag(60)
                            Text("Mai").tag(0)
                        }
                        .labelsHidden()
                        .onChange(of: clipboard) { _, v in Preferences.clipboardSeconds = v }
                    }

                    divider
                    section("Password generate")

                    row("Lunghezza", "Quanti caratteri hanno quelle create dal dado.") {
                        Picker("", selection: $length) {
                            ForEach([12, 16, 20, 24, 32], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .onChange(of: length) { _, v in Preferences.passwordLength = v }
                    }

                    // Chiave di recupero e importazione dati: solo Mac. Sul
                    // telefono la chiave è già quella fatta di là (o niente,
                    // se i cassetti non sono ancora arrivati) — mostrarne
                    // una seconda qui confonderebbe soltanto.
                    #if os(macOS)
                    divider
                    section("Chiave di recupero")

                    Text(RecoveryKit.exists
                         ? "C'è già. Rigenerandola la vecchia smette di funzionare."
                         : "Non ce n'è nessuna: senza, una master password dimenticata vuol dire vault persi.")
                        .font(Theme.mono(10))
                        .foregroundStyle(RecoveryKit.exists ? Theme.inkSoft : Theme.danger)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let newRecovery {
                        Text(newRecovery)
                            .font(Theme.mono(14, .semibold))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Theme.paperRaised)
                            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
                        Text("Annotala adesso: chiudendo qui non si rivede più.")
                            .font(Theme.mono(10, .semibold))
                            .foregroundStyle(Theme.danger)
                    }

                    Button { confirmRegenerate = true } label: {
                        Label(RecoveryKit.exists ? "Rigenera la chiave" : "Genera la chiave",
                              systemImage: "key.horizontal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())

                    divider
                    section("Dati")

                    // Un comando solo: a capire cosa gli hai dato (cassetti
                    // esportati, .kdbx, .csv, archivi .1pux) ci pensa lui.
                    Button {
                        VaultTransfer.chooseImport { urls in
                            guard !urls.isEmpty else { return }
                            let chiave = MasterKey.session
                            leggendo = true
                            note = nil; error = nil
                            Task {
                                let previews = await VaultTransfer.inspectAny(urls, key: chiave)
                                leggendo = false
                                importJob = ImportJob(previews: previews)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if leggendo {
                                ProgressView().controlSize(.small)
                                Text("Leggo…")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text("Importa password")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(leggendo)
                    #endif


                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [VaultFileManager.shared.projectsDirectory]
                        )
                    } label: {
                        Label("Mostra i vault nel Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())

                    divider
                    section("Estensione Safari")
                    Text("Compila utente e password nei siti, direttamente da Safari: un tasto 🔒 compare sopra ogni campo password.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if estensioneSafariAttiva {
                        Label("Attivata", systemImage: "checkmark.circle.fill")
                            .font(Theme.mono(11, .semibold))
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.yellow.opacity(0.5))
                            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
                    } else {
                        Button {
                            SFSafariApplication.showPreferencesForExtension(
                                withIdentifier: "com.antonioscirica.hush.safariextension",
                                completionHandler: { error in
                                    guard error != nil else { return }
                                    DispatchQueue.main.async { erroreSafariManuale = true }
                                }
                            )
                        } label: {
                            Text("Attiva in Safari")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())

                        if erroreSafariManuale {
                            Text("Non riesco ad aprirlo da qui: vai a mano su Safari → Impostazioni → Estensioni → attiva Hush.")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.danger)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    divider
                    section("Estensione Chrome")
                    Text("Chrome non può leggere il Portachiavi come fa Safari: la prima volta va incollato un token, una volta sola. Copialo qui, poi incollalo nel popup dell'estensione.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        let token = BridgeToken.ensureExists()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(token, forType: .string)
                        tokenChromeCopiato = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { tokenChromeCopiato = false }
                    } label: {
                        Text(tokenChromeCopiato ? "Copiato" : "Copia token per Chrome")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())

                    // Nascosta finché l'app OAuth non è pubblicata su Google
                    // (oggi solo utenti di test possono collegarsi, e i
                    // token scadrebbero ogni 7 giorni): il codice c'è già,
                    // pronto per quando ha senso mostrarla davvero.
                    if Self.mostraBackupDrive {
                    divider
                    section("Backup su Google Drive")
                    if driveConnesso {
                        Text("Collegato con \(GoogleTokenStore.email ?? "il tuo account"). Un backup dei cassetti parte da sé ogni sette giorni, in una cartella «Hush Backup» sul tuo Drive.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ultimoBackupTesto)
                            .font(Theme.mono(10, .semibold))
                            .foregroundStyle(Theme.ink)

                        Button {
                            driveBackupInCorso = true
                            Task {
                                await GoogleDriveBackup.backupAll()
                                driveBackupInCorso = false
                            }
                        } label: {
                            Label(driveBackupInCorso ? "Carico…" : "Backup ora", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(driveBackupInCorso)

                        Button {
                            GoogleDriveAuth.shared.disconnect()
                            driveConnesso = false
                        } label: {
                            Text("Scollega").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                    } else {
                        Text("Un backup automatico dei tuoi cassetti (già cifrati) su Google Drive, una volta collegato l'account. Se il Mac si rompe, li ritrovi lì.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if let driveErrore {
                            Text(driveErrore).font(Theme.mono(10)).foregroundStyle(Theme.danger)
                        }
                        Button {
                            driveErrore = nil
                            GoogleDriveAuth.shared.connect { result in
                                switch result {
                                case .success:
                                    driveConnesso = true
                                    Task { await GoogleDriveBackup.backupAll() } // il primo, subito
                                case .failure(let error):
                                    driveErrore = error.localizedDescription
                                }
                            }
                        } label: {
                            Label("Connetti Google Drive", systemImage: "icloud.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                    }
                    } // mostraBackupDrive

                    divider
                    section("Manda al telefono")
                    Text("Via WiFi, senza passare da nessun server. Resta acceso solo quanto ti serve: fuori casa il Mac non deve annunciarsi in giro.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    macSyncBox
                    #endif

                    #if os(iOS)
                    divider
                    section("Sincronizza col Mac")
                    Text("Via WiFi, senza server. Le voci nuove e modificate viaggiano nei due sensi: quello che aggiungi qui finisce sul Mac, e viceversa.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                    iphoneSyncBox
                    #endif

                    divider
                    Link("Norme sulla privacy", destination: URL(string: "https://hush-topaz.vercel.app/privacy")!)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.inkSoft)

                    if importando {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Importo i cassetti…").font(Theme.mono(11))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    if let note {
                        Text(note).font(Theme.mono(11)).foregroundStyle(Theme.ink)
                    }
                    if let error {
                        Text(error).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                    }

                    divider
                    Text(versione)
                        .font(Theme.mono(9))
                        .foregroundStyle(Theme.inkSoft)
                }
                .padding(.trailing, 4)
            }

            Button("Chiudi") { onClose() }
                .buttonStyle(InkButtonStyle(prominent: true))
                .padding(.top, 18)
        }
        #if os(iOS)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        .padding(30)
        .frame(width: 460, height: 560)
        #endif
        .sheet(item: $importJob) { job in
            ImportPreviewView(previews: job.previews) { scelti in
                importJob = nil
                importando = true
                let voci = scelti.reduce(0) { $0 + $1.entries.count }
                // la cifratura di ogni cassetto è un Argon2id: fuori dal
                // thread principale, se no la finestra si pianta
                Task {
                    do {
                        let n = try await VaultTransfer.importChosenAsync(scelti)
                        note = "Importati \(n) cassetti, \(voci) voci."
                        error = nil
                    } catch {
                        self.error = "Importazione non riuscita: \(error.localizedDescription)"
                    }
                    importando = false
                }
            } onCancel: {
                importJob = nil
            }
            .sheetPaperLocal()
        }
        .alert("Staccare la licenza da questo computer?", isPresented: $confirmDetach) {
            Button("Annulla", role: .cancel) {}
            Button("Stacca", role: .destructive) { License.detach(); onClose() }
        } message: {
            Text("Hush tornerà bloccato qui e potrai attivare la licenza su un altro Mac.\n\nI cassetti restano su questo computer: se ti servono di là, esportali PRIMA di staccare.")
        }
        .alert("Rigenerare la chiave di recupero?", isPresented: $confirmRegenerate) {
            Button("Annulla", role: .cancel) {}
            Button("Rigenera", role: .destructive) { regenerateRecovery() }
        } message: {
            Text(RecoveryKit.exists
                 ? "La chiave che hai stampato smetterà di funzionare all'istante. Quella nuova va annotata subito: se chiudi questa finestra senza copiarla, resti senza via di recupero.\n\nFallo se la vecchia è finita in mani sbagliate: è l'unico modo di revocarla."
                 : "La chiave va annotata subito: se chiudi questa finestra senza copiarla, resti senza via di recupero.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
            handleCSV(result)
        }
        // l'ascolto e l'avviso da accettare li gestisce RootView, che c'è
        // sempre: qui in Impostazioni si vede solo lo stato condiviso
        #if os(macOS)
        .task { aggiornaStatoEstensioneSafari() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // si torna qui da Impostazioni di Sistema dopo averla attivata:
            // niente da ricaricare a mano, si vede da sé
            aggiornaStatoEstensioneSafari()
        }
        #endif
    }

    #if os(macOS)
    private var ultimoBackupTesto: String {
        guard let data = GoogleTokenStore.lastBackup else { return "Nessun backup ancora." }
        let giorni = Int(Date().timeIntervalSince(data) / 86_400)
        if giorni <= 0 { return "Ultimo backup: oggi." }
        if giorni == 1 { return "Ultimo backup: ieri." }
        return "Ultimo backup: \(giorni) giorni fa."
    }

    private func aggiornaStatoEstensioneSafari() {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: "com.antonioscirica.hush.safariextension") { state, _ in
            DispatchQueue.main.async {
                estensioneSafariAttiva = state?.isEnabled ?? false
            }
        }
    }
    #endif

    // MARK: - Pezzi

    private var divider: some View {
        Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)
    }

    #if os(macOS)
    @ViewBuilder
    private var macSyncBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch sync.stato {
            case .fermo, .inCerca:
                Button("Accendi la ricerca") { sync.avviaAscolto() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)

            case .inAttesa:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("In ascolto: apri Hush sul telefono e cerca il Mac")
                        .font(Theme.mono(11))
                }
                .foregroundStyle(Theme.inkSoft)
                Button("Spegni") { sync.ferma() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)

            case .collegato(let nome):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Collegato a \(nome), mando i cassetti…")
                        .font(Theme.mono(11))
                }
                .foregroundStyle(Theme.ink)

            case .trasferendo(let fatti, let totale):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Invio in corso… \(fatti)/\(totale)")
                        .font(Theme.mono(11, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .fatto(let n):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("\(n) cassetti mandati al telefono")
                        .font(Theme.mono(12, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .errore(let messaggio):
                Text(messaggio)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
    #endif

    #if os(iOS)
    /// Sync bidirezionale col Mac, dal telefono: cerca, ricevi, fondi,
    /// rimanda indietro il risultato. Il Mac (sbloccato) è già in ascolto.
    @ViewBuilder
    private var iphoneSyncBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch sync.stato {
            case .fermo, .inAttesa:
                Button("Cerca il Mac sulla rete") { preparaMergeDiRitorno(); sync.avviaRicerca() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)

            case .inCerca:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(sync.trovati.isEmpty ? "Cerco un Mac con Hush aperto sulla stessa rete…" : "Trovati:")
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
                    Text("Collegato a \(nome)…").font(Theme.mono(11))
                }
                .foregroundStyle(Theme.ink)

            case .trasferendo(let fatti, let totale):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Sincronizzo… \(fatti)/\(totale)").font(Theme.mono(11, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .fatto:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                    Text("Sincronizzato").font(Theme.mono(12, .semibold))
                }
                .foregroundStyle(Theme.ink)

            case .errore(let messaggio):
                Text(messaggio).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                Button("Riprova") { preparaMergeDiRitorno(); sync.avviaRicerca() }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.paperRaised)
        .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
        .onDisappear { sync.ferma() }
    }

    /// Alla ricezione dei cassetti del Mac: fusione voce per voce, poi il
    /// risultato riparte verso il Mac perché fonda a specchio. La cartella
    /// d'atterraggio va spostata subito (LocalSync la cancella appena il
    /// callback ritorna) e il lavoro pesante sta fuori dal main thread.
    private func preparaMergeDiRitorno() {
        sync.alCompletamento = { cartella in
            guard let chiave = MasterKey.session else { return }
            let lavoro = FileManager.default.temporaryDirectory
                .appendingPathComponent("hush-merge-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.moveItem(at: cartella, to: lavoro)
            Task.detached(priority: .userInitiated) {
                _ = try? VaultMerge.mergeAll(from: lavoro, key: chiave)
                try? FileManager.default.removeItem(at: lavoro)
                await MainActor.run {
                    AutoFillIdentities.sync()
                    // viaggio di ritorno: il risultato fuso torna al Mac
                    guard let peer = LocalSync.shared.peerConnesso else { return }
                    Task {
                        guard let (_, folder) = try? await VaultTransfer.exportAsync(
                            to: FileManager.default.temporaryDirectory
                        ) else { return }
                        let files = (try? FileManager.default.contentsOfDirectory(
                            at: folder, includingPropertiesForKeys: nil
                        )) ?? []
                        LocalSync.shared.pronto(files: files, per: peer)
                    }
                }
            }
        }
    }
    #endif

    private func section(_ title: String) -> some View {
        Text(title)
            .font(Theme.mono(10, .semibold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Theme.inkSoft)
    }

    private func row<Control: View>(_ title: String, _ detail: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.mono(12, .semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            // Colonna allineata a destra. I controlli NON hanno una larghezza
            // propria: dandogliela, il menu a tendina si centrava dentro il
            // suo riquadro e restava più stretto dell'interruttore. Liberi e
            // allineati in coda, i bordi destri cadono sulla stessa linea.
            control()
                .fixedSize()
        }
    }

    private var reminderText: String {
        guard MasterKey.biometryEnabled else {
            return "La password si digita a ogni apertura."
        }
        guard typeAgain > 0 else {
            return "Non verrà più richiesta: se la dimentichi non c'è modo di recuperarla."
        }
        let left = max(0, typeAgain - Int(MasterKey.sinceTyped / 86_400))
        return left == 0
            ? "Alla prossima apertura la password va riscritta a mano."
            : "Mancano \(left) giorni alla prossima volta."
    }

    // MARK: - Azioni

    /// Accendere il dito significa mettere la password nel Portachiavi: si può
    /// fare solo a scrigno aperto, perché è lì che la chiave è in memoria.
    private func applyBiometry(_ on: Bool) {
        error = nil
        guard on else {
            MasterKey.disableBiometry()
            return
        }
        guard let key = MasterKey.session else {
            error = "Bloccato: riapri e riprova."
            biometry = false
            return
        }
        MasterKey.enableBiometry(password: key) { esito in
            if case .failure(let error) = esito {
                self.error = "Non è stato possibile attivarlo: \(error.localizedDescription)"
                biometry = false
            }
        }
    }

    /// La chiave nuova si può fare solo a scrigno aperto: serve la master
    /// password in chiaro per cifrarcela dentro.
    private func regenerateRecovery() {
        error = nil
        guard let key = MasterKey.session else {
            error = "Bloccato: riapri e riprova."
            return
        }
        do {
            newRecovery = try RecoveryKit.create(masterPassword: key)
        } catch {
            self.error = "Non è stato possibile generarla: \(error.localizedDescription)"
        }
    }

    private func handleCSV(_ result: Result<URL, Error>) {
        error = nil; note = nil
        guard case .success(let url) = result else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            PendingImport.entries = try CSVImport.parse(contentsOf: url)
            PendingImport.projectName = url.deletingPathExtension().lastPathComponent
            note = "\(PendingImport.entries.count) voci importate in un nuovo cassetto."
            onImport()
        } catch {
            self.error = error.localizedDescription
        }
    }
}


private extension View {
    /// Fondo di carta su tutta la finestra della sheet (vedi sheetPaper in
    /// ProjectsHomeView: quello è privato di quel file).
    func sheetPaperLocal() -> some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            self
        }
        .preferredColorScheme(.light)
    }
}
