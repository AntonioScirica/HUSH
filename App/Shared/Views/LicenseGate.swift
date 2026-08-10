import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Promemoria della prova: una targhetta piccola nell'angolo in alto a
/// sinistra, non una fascia a tutta larghezza.
///
/// La fascia copriva i comandi del cassetto aperto, che stanno in cima: un
/// avviso che nasconde i pulsanti è peggio del problema che risolve.
struct TrialBanner: View {
    let onOpenSettings: () -> Void

    var body: some View {
        Button(action: onOpenSettings) {
            HStack(spacing: 7) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                Text(License.trialDaysLeft == 1
                     ? "Ultimo giorno"
                     : "Prova · \(License.trialDaysLeft) giorni")
                    .font(Theme.mono(10, .semibold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.yellow)
            .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 1.2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Attiva la licenza")
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
                    IndexLabel(text: "La prova è finita")
                    Rectangle().fill(Theme.line).frame(height: 1.2)
                }

                Text("I sette giorni sono passati. Per continuare a usare\nHush serve una licenza.")
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Incolla qui la licenza", text: $licenseText, axis: .vertical)
                    .textFieldStyle(PaperFieldStyle())
                    .lineLimit(2...4)

                if let error {
                    Text(error).font(Theme.mono(11)).foregroundStyle(Theme.danger)
                }
                if let note {
                    Text(note).font(Theme.mono(11)).foregroundStyle(Theme.ink)
                }

                Button("Attiva") {
                    if License.register(licenseText) != nil {
                        onActivated()
                    } else {
                        error = "Questa licenza non è valida."
                    }
                }
                .buttonStyle(InkButtonStyle(prominent: true))
                .disabled(licenseText.isEmpty)
                .opacity(licenseText.isEmpty ? 0.4 : 1)

                Rectangle().fill(Theme.line.opacity(0.4)).frame(height: 1)

                // I vault restano tuoi anche senza licenza: si possono
                // portare via in qualunque momento.
                VStack(alignment: .leading, spacing: 8) {
                    Text("I tuoi cassetti restano tuoi")
                        .font(Theme.mono(11, .semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Puoi portarli via anche adesso: restano chiusi con la tua password, e li riapri dove vuoi.")
                        .font(Theme.mono(10))
                        .foregroundStyle(Theme.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    #if os(macOS)
                    Button {
                        VaultTransfer.chooseExportFolder { folder in
                            guard let folder else { return }
                            Task { do {
                                let esito = try await VaultTransfer.exportAsync(to: folder)
                                note = "Esportati \(esito.count) cassetti in «\(esito.folder.lastPathComponent)»."
                                error = nil
                                #if os(macOS)
                                NSWorkspace.shared.activateFileViewerSelecting([esito.folder])
                                #endif
                            } catch {
                                self.error = "Esportazione non riuscita: \(error.localizedDescription)"
                            } }
                        }
                    } label: {
                        Label("Esporta tutti i cassetti", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(OutlineButtonStyle())
                    #endif
                }

                Spacer(minLength: 0)
            }
            #if os(iOS)
            .padding(28)
            .frame(maxWidth: .infinity)
            #else
            .padding(40)
            .frame(width: 520)
            #endif
        }
        .preferredColorScheme(.light)
    }
}
