import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Impostazioni dello scrigno: chiave d'accesso, cosa scade da solo e come
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
    @State private var symbols = Preferences.passwordSymbols
    @State private var typeAgain = Preferences.typeAgainDays
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                IndexLabel(text: "impostazioni")
                Rectangle().fill(Theme.line).frame(height: 1.2)
            }
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("licenza")

                    if let info = License.active {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal")
                            Text("attiva · \(info.email)")
                                .font(Theme.mono(11, .semibold))
                        }
                        .foregroundStyle(Theme.ink)

                        Text("vale per un computer. per spostarla su un altro Mac staccala da qui, poi esporta i cassetti e riattivala di là.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)

                        Button { confirmDetach = true } label: {
                            Label("stacca da questo computer", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                    } else {
                        Text(License.trialDaysLeft > 0
                             ? "prova: mancano \(License.trialDaysLeft) giorni."
                             : "la prova è finita: inserisci la licenza per continuare.")
                            .font(Theme.mono(10))
                            .foregroundStyle(License.trialDaysLeft > 0 ? Theme.inkSoft : Theme.danger)

                        // Dirlo prima, non quando succede: chi affida le
                        // proprie password a un programma ha diritto di
                        // sapere in partenza cosa gli resta in mano.
                        Text("passati i 7 giorni Scrigno si blocca: i cassetti non si aprono più da qui finché non attivi la licenza.\n\nquello che ci hai messo dentro resta comunque tuo: dalla schermata di blocco puoi sempre esportarlo, e sono file .kdbx che si aprono con KeePass o qualunque programma compatibile, anche senza Scrigno.")
                            .font(Theme.mono(10))
                            .foregroundStyle(Theme.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField("incolla qui la licenza", text: $licenseText, axis: .vertical)
                            .textFieldStyle(PaperFieldStyle())
                            .lineLimit(2...4)

                        Button {
                            if License.register(licenseText) != nil {
                                licenseText = ""; note = "licenza attivata."; error = nil
                            } else {
                                error = "questa licenza non è valida."
                            }
                        } label: {
                            Label("attiva", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(OutlineButtonStyle())
                        .disabled(licenseText.isEmpty)
                    }

                    divider
                    section("chiave d'accesso")

                    if MasterKey.biometryAvailable {
                        row("sblocco col dito",
                            "apre lo scrigno col sensore invece della password.") {
                            Toggle("", isOn: $biometry)
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .onChange(of: biometry) { _, on in applyBiometry(on) }
                        }
                    }

                    row("riscrivi la password ogni",
                        "col dito soltanto la si dimentica, e qui non c'è nessun recupero.") {
                        Picker("", selection: $typeAgain) {
                            Text("3 giorni").tag(3)
                            Text("7 giorni").tag(7)
                            Text("14 giorni").tag(14)
                            Text("30 giorni").tag(30)
                            Text("mai").tag(0)
                        }
                        .labelsHidden()
                        .onChange(of: typeAgain) { _, v in Preferences.typeAgainDays = v }
                    }

                    Text(reminderText)
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)

                    divider
                    section("da sé")

                    row("richiudi dopo",
                        "lo scrigno si blocca da solo se lo lasci lì aperto.") {
                        Picker("", selection: $autolock) {
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("mai").tag(0)
                        }
                        .labelsHidden()
                        .onChange(of: autolock) { _, v in Preferences.autolockMinutes = v }
                    }

                    row("svuota gli appunti dopo",
                        "una password copiata la legge qualunque cosa incolli dopo.") {
                        Picker("", selection: $clipboard) {
                            Text("15 s").tag(15)
                            Text("30 s").tag(30)
                            Text("60 s").tag(60)
                            Text("mai").tag(0)
                        }
                        .labelsHidden()
                        .onChange(of: clipboard) { _, v in Preferences.clipboardSeconds = v }
                    }

                    divider
                    section("password generate")

                    row("lunghezza", "quanti caratteri hanno quelle create dal dado.") {
                        Picker("", selection: $length) {
                            ForEach([12, 16, 20, 24, 32], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .onChange(of: length) { _, v in Preferences.passwordLength = v }
                    }

                    row("con simboli", "alcuni siti non li accettano: qui li togli.") {
                        Toggle("", isOn: $symbols)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: symbols) { _, v in Preferences.passwordSymbols = v }
                    }

                    divider
                    section("chiave di recupero")

                    Text(RecoveryKit.exists
                         ? "c'è già. rigenerandola la vecchia smette di funzionare."
                         : "non ce n'è nessuna: senza, una master password dimenticata vuol dire vault persi.")
                        .font(Theme.mono(10))
                        .foregroundStyle(RecoveryKit.exists ? Theme.inkSoft : Theme.danger)
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
                        Text("annotala adesso: chiudendo qui non si rivede più.")
                            .font(Theme.mono(10, .semibold))
                            .foregroundStyle(Theme.danger)
                    }

                    Button { confirmRegenerate = true } label: {
                        Label(RecoveryKit.exists ? "rigenera la chiave" : "genera la chiave",
                              systemImage: "key.horizontal")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())

                    divider
                    section("dati")

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
                                Text("leggo…")
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                Text("importa password")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(leggendo)

                    Text("da un altro Mac, da 1Password (.1pux), da un .csv esportato da Bitwarden, LastPass o dal browser.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [VaultFileManager.shared.projectsDirectory]
                        )
                    } label: {
                        Label("mostra i vault nel Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())

                    Text("i .kdbx stanno lì: copiali dove vuoi per farne un backup.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)

                    if importando {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("importo i cassetti…").font(Theme.mono(11))
                        }
                        .foregroundStyle(Theme.ink)
                    }
                    if let note {
                        Text(note).font(Theme.mono(11)).foregroundStyle(Theme.ink)
                    }
                    if let error {
                        Text(error).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                    }
                }
                .padding(.trailing, 4)
            }

            Button("chiudi") { onClose() }
                .buttonStyle(InkButtonStyle(prominent: true))
                .padding(.top, 18)
        }
        .padding(30)
        .frame(width: 460, height: 560)
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
                        note = "importati \(n) cassetti, \(voci) voci."
                        error = nil
                    } catch {
                        self.error = "importazione non riuscita: \(error.localizedDescription)"
                    }
                    importando = false
                }
            } onCancel: {
                importJob = nil
            }
            .sheetPaperLocal()
        }
        .alert("Staccare la licenza da questo computer?", isPresented: $confirmDetach) {
            Button("annulla", role: .cancel) {}
            Button("stacca", role: .destructive) { License.detach(); onClose() }
        } message: {
            Text("Scrigno tornerà bloccato qui e potrai attivare la licenza su un altro Mac.\n\nI cassetti restano su questo computer: se ti servono di là, esportali PRIMA di staccare.")
        }
        .alert("Rigenerare la chiave di recupero?", isPresented: $confirmRegenerate) {
            Button("annulla", role: .cancel) {}
            Button("rigenera", role: .destructive) { regenerateRecovery() }
        } message: {
            Text(RecoveryKit.exists
                 ? "La chiave che hai stampato smetterà di funzionare all'istante. Quella nuova va annotata subito: se chiudi questa finestra senza copiarla, resti senza via di recupero.\n\nFallo se la vecchia è finita in mani sbagliate: è l'unico modo di revocarla."
                 : "La chiave va annotata subito: se chiudi questa finestra senza copiarla, resti senza via di recupero.")
        }
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
            handleCSV(result)
        }
    }

    // MARK: - Pezzi

    private var divider: some View {
        Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)
    }

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
            return "la password si digita a ogni apertura."
        }
        guard typeAgain > 0 else {
            return "non verrà più richiesta: se la dimentichi non c'è modo di recuperarla."
        }
        let left = max(0, typeAgain - Int(MasterKey.sinceTyped / 86_400))
        return left == 0
            ? "alla prossima apertura la password va riscritta a mano."
            : "mancano \(left) giorni alla prossima volta."
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
            error = "scrigno bloccato: riapri e riprova."
            biometry = false
            return
        }
        do {
            try MasterKey.enableBiometry(password: key)
        } catch {
            self.error = "non è stato possibile attivarlo: \(error.localizedDescription)"
            biometry = false
        }
    }

    /// La chiave nuova si può fare solo a scrigno aperto: serve la master
    /// password in chiaro per cifrarcela dentro.
    private func regenerateRecovery() {
        error = nil
        guard let key = MasterKey.session else {
            error = "scrigno bloccato: riapri e riprova."
            return
        }
        do {
            newRecovery = try RecoveryKit.create(masterPassword: key)
        } catch {
            self.error = "non è stato possibile generarla: \(error.localizedDescription)"
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
