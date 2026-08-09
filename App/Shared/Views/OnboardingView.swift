import SwiftUI
import UniformTypeIdentifiers
import AppKit

private extension View {
    func themedImportRow() -> some View {
        padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.paperRaised)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 1))
    }
}

/// Primo avvio: si presenta lo scrigno, si sceglie la master password e —
/// se la macchina ce l'ha — si attiva il dito. Stessa carta, stesso
/// inchiostro, stessi divider numerati del resto dell'app.
struct OnboardingView: View {
    let onDone: () -> Void

    private enum Step: Int, CaseIterable {
        case intro, password, recovery, biometry, importing, ready
    }

    @State private var step: Step = .intro
    @State private var password = ""
    @State private var confirm = ""
    @State private var reveal = false
    @State private var error: String?
    @FocusState private var passwordFocused: Bool

    @State private var showFileImporter = false
    @State private var importedCount = 0
    /// Chiave di recupero: si vede solo qui, una volta.
    @State private var recoveryKey = ""
    @State private var recoverySaved = false

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
                    case .importing: importStep
                    case .ready:     ready
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                footer
            }
            .padding(40)
            .frame(width: 520, height: 560)
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

    private var title: String {
        switch step {
        case .intro:     return "benvenuto"
        case .password:  return "la tua unica password"
        case .recovery:  return "la chiave di scorta"
        case .biometry:  return "sblocco col dito"
        case .importing: return "porta dentro quelle che hai già"
        case .ready:     return "tutto pronto"
        }
    }

    // MARK: - Passi

    private var intro: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 0) {
                Text("SCRIGNO")
                    .font(Theme.display(48))
                    .kerning(-1)
                    .foregroundStyle(Theme.ink)
                Text("kdbx")
                    .font(Theme.mono(10, .bold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.yellow, in: Capsule())
                    .rotationEffect(.degrees(-8))
                    .offset(x: -4, y: 4)
            }

            VStack(alignment: .leading, spacing: 14) {
                bullet("un caveau, non un servizio",
                       "i tuoi dati restano su questo computer. nessun account, nessun server.")
                bullet("un cassetto per progetto",
                       "ogni progetto è un file .kdbx a sé, cifrato con AES-256 e Argon2id.")
                bullet("una password per tutto",
                       "una sola chiave apre l'intero scrigno: quella che scegli adesso.")
                bullet("7 giorni di prova",
                       "poi serve una licenza. i cassetti restano tuoi: sono file .kdbx, si esportano e si aprono anche con KeePass.")
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
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var passwordStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("scegline una lunga e che ricordi. non si può recuperare:\nnon esiste nessuno a cui chiederla.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Group {
                    if reveal {
                        TextField("master password", text: $password)
                    } else {
                        SecureField("master password", text: $password)
                    }
                }
                .textFieldStyle(PaperFieldStyle())
                .focused($passwordFocused)

                Button { reveal.toggle() } label: {
                    Image(systemName: reveal ? "eye.slash" : "eye")
                        .foregroundStyle(Theme.inkSoft)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
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
                .font(Theme.mono(15, .semibold))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))

            HStack(spacing: 10) {
                Button {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(recoveryKey, forType: .string)
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

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 11))
                Text("vale quanto la master password: chi ce l'ha entra. stampala o mettila in cassaforte, non lasciarla sul computer accanto ai vault.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.mono(10))
            .foregroundStyle(Theme.inkSoft)

            if recoverySaved {
                Text("non verrà più mostrata.")
                    .font(Theme.mono(10, .semibold))
                    .foregroundStyle(Theme.danger)
            }
        }
    }

    private func saveRecoveryToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Scrigno — chiave di recupero.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let testo = """
            SCRIGNO — CHIAVE DI RECUPERO

            \(recoveryKey)

            Serve a rientrare se dimentichi la master password.
            Vale quanto la password stessa: chi ce l'ha apre tutto.
            Stampala e conservala lontano dal computer.
            """
            try? testo.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private var biometryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "touchid")
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(Theme.ink)
            Text("puoi aprire lo scrigno col dito invece di riscrivere la\npassword ogni volta. resta tutto su questo computer:\nla password va nel Portachiavi, protetta dal sensore.")
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

    /// Import da un altro gestore. Il CSV è il minimo comun denominatore:
    /// 1Password, Bitwarden, LastPass, Chrome e Safari lo esportano tutti.
    private var importStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.ink)

            Text("se usi già 1Password, Bitwarden, LastPass o le password\ndel browser, esporta un .csv da lì e caricalo qui: finisce\ntutto in un cassetto solo, che poi puoi riordinare.")
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
                    Label("scegli un file .csv", systemImage: "doc.badge.plus")
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
        .fileImporter(isPresented: $showFileImporter,
                      allowedContentTypes: [.commaSeparatedText, .text, .plainText]) { result in
            handleCSV(result)
        }
    }

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
            Text("lo scrigno è chiuso a chiave.")
                .font(Theme.display(26))
                .foregroundStyle(Theme.ink)
            Text("da qui in poi vedrai la parete dei cassetti: uno per\nprogetto. creane uno col + e mettici dentro la prima\npassword.")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Navigazione

    private var footer: some View {
        HStack(spacing: 10) {
            // pallini di avanzamento
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Rectangle()
                        .fill(s.rawValue <= step.rawValue ? Theme.ink : Theme.line.opacity(0.3))
                        .frame(width: 16, height: 3)
                }
            }

            Spacer()

            if step == .biometry {
                Button("non ora") { step = .importing }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(width: 130)
            }
            if step == .importing && importedCount == 0 {
                Button("salta") { step = .ready }
                    .buttonStyle(OutlineButtonStyle())
                    .frame(width: 130)
            }

            Button(primaryLabel) { advance() }
                .buttonStyle(InkButtonStyle(prominent: true))
                .frame(width: 170)
                .disabled(!canAdvance)
                .opacity(canAdvance ? 1 : 0.4)
        }
    }

    private var primaryLabel: String {
        switch step {
        case .intro:     return "comincia"
        case .password:  return "imposta"
        case .recovery:  return recoverySaved ? "avanti" : "l'ho messa al sicuro"
        case .biometry:  return "attiva"
        case .importing: return importedCount > 0 ? "avanti" : "scegli file"
        case .ready:     return "entra"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case .password:
            return password.count >= 8 && password == confirm
        default:
            return true
        }
    }

    private func advance() {
        error = nil
        switch step {
        case .intro:
            step = .password

        case .password:
            guard password.count >= 8 else {
                error = "almeno 8 caratteri."
                return
            }
            guard password == confirm else {
                error = "le due password non combaciano."
                return
            }
            MasterKey.configure(password: password)
            // la chiave di scorta nasce subito: dopo, senza la master
            // password in mano, non si potrebbe più cifrarci dentro niente
            recoveryKey = (try? RecoveryKit.create(masterPassword: password)) ?? ""
            step = .recovery

        case .recovery:
            guard recoverySaved else { recoverySaved = true; return }
            step = MasterKey.biometryAvailable ? .biometry : .importing

        case .biometry:
            do {
                try MasterKey.enableBiometry(password: password)
                step = .importing
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
}
