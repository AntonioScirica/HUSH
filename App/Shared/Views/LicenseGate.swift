import SwiftUI
import AppKit

/// Striscia sempre in vista durante la prova: quanti giorni restano e come si
/// attiva. Sparisce solo a licenza attivata.
struct TrialBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 11, weight: .semibold))
            Text(License.trialDaysLeft == 1
                 ? "ultimo giorno di prova"
                 : "prova: restano \(License.trialDaysLeft) giorni")
                .font(Theme.mono(11, .semibold))
            Spacer(minLength: 0)
            Button("attiva la licenza") { onOpenSettings() }
                .buttonStyle(.plain)
                .font(Theme.mono(11, .semibold))
                .underline()
        }
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.yellow)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.ink).frame(height: 1.2)
        }
    }
}

/// Schermata di blocco a prova finita.
///
/// Blocca davvero: senza licenza non si arriva ai cassetti. Resta però una via
/// d'uscita che non toglie a nessuno la roba propria — l'esportazione dei
/// vault. Sono file cifrati con la master password, appartengono a chi li ha
/// scritti, e tenerli in ostaggio per far pagare sarebbe un'altra cosa.
struct LicenseWall: View {
    @State private var licenseText = ""
    @State private var error: String?
    @State private var note: String?
    let onActivated: () -> Void

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    IndexLabel(text: "la prova è finita")
                    Rectangle().fill(Theme.line).frame(height: 1.2)
                }

                Text("i sette giorni sono passati. per continuare a usare\nScrigno serve una licenza.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("incolla qui la licenza", text: $licenseText, axis: .vertical)
                    .textFieldStyle(PaperFieldStyle())
                    .lineLimit(2...4)

                if let error {
                    Text(error).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                }
                if let note {
                    Text(note).font(Theme.mono(11)).foregroundStyle(Theme.ink)
                }

                Button("attiva") {
                    if License.register(licenseText) != nil {
                        onActivated()
                    } else {
                        error = "questa licenza non è valida."
                    }
                }
                .buttonStyle(InkButtonStyle(prominent: true))
                .disabled(licenseText.isEmpty)
                .opacity(licenseText.isEmpty ? 0.4 : 1)

                Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)

                // I vault restano tuoi anche senza licenza: si possono
                // portare via in qualunque momento.
                VStack(alignment: .leading, spacing: 8) {
                    Text("i tuoi cassetti restano tuoi")
                        .font(Theme.mono(11, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("puoi esportarli anche adesso: sono file .kdbx cifrati con la tua master password, si aprono con qualunque programma compatibile con KeePass.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        VaultTransfer.chooseExportFolder { folder in
                            guard let folder else { return }
                            do {
                                let esito = try VaultTransfer.export(to: folder)
                                note = "esportati \(esito.count) cassetti in «\(esito.folder.lastPathComponent)»."
                                error = nil
                                NSWorkspace.shared.activateFileViewerSelecting([esito.folder])
                            } catch {
                                self.error = "esportazione non riuscita: \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        Label("esporta tutti i cassetti", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                }

                Spacer(minLength: 0)
            }
            .padding(40)
            .frame(width: 520)
        }
        .preferredColorScheme(.light)
    }
}
