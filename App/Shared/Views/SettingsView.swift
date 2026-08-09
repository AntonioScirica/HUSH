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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                IndexLabel(number: 1, text: "impostazioni")
                Rectangle().fill(Theme.line).frame(height: 1.2)
            }
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
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
                        }
                        .labelsHidden()
                        .frame(width: 130)
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
                        .frame(width: 130)
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
                        .frame(width: 130)
                        .onChange(of: clipboard) { _, v in Preferences.clipboardSeconds = v }
                    }

                    divider
                    section("password generate")

                    row("lunghezza", "quanti caratteri hanno quelle create dal dado.") {
                        Picker("", selection: $length) {
                            ForEach([12, 16, 20, 24, 32], id: \.self) { Text("\($0)").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                        .onChange(of: length) { _, v in Preferences.passwordLength = v }
                    }

                    row("con simboli", "alcuni siti non li accettano: qui li togli.") {
                        Toggle("", isOn: $symbols)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .onChange(of: symbols) { _, v in Preferences.passwordSymbols = v }
                    }

                    divider
                    section("dati")

                    Button { showImporter = true } label: {
                        Label("importa da un .csv…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())

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
            // colonna di larghezza fissa allineata a destra: menu a tendina e
            // interruttori hanno ingombri diversi e, lasciati liberi, i loro
            // bordi destri non cadevano sulla stessa linea
            control()
                .frame(width: 130, alignment: .trailing)
        }
    }

    private var reminderText: String {
        guard MasterKey.biometryEnabled else {
            return "la password si digita a ogni apertura."
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
