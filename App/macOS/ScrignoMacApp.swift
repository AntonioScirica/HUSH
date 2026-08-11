import SwiftUI
import Sparkle

@main
struct ScrignoMacApp: App {
    /// Finestra di misura fissa: la parete, la porta del caveau e le schede
    /// che si agganciano alle cartelle sono tarate su questo formato.
    /// È la misura del CONTENUTO: la finestra ci aggiunge sopra la barra del
    /// titolo nascosta (32 pt), e viene fuori il 829×612 di prima.
    private static let windowSize = CGSize(width: 829, height: 580)

    /// Controlla da sé, in background, se c'è una versione nuova sul feed
    /// (vedi SUFeedURL in project.yml) — l'utente vede solo il pannello
    /// quando c'è davvero qualcosa di nuovo da installare.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    /// ⌃⌥H da qualunque app: apre il popup per aggiungere una password al
    /// volo, senza passare dalla finestra principale. Va tenuta in vita
    /// (un riferimento forte) o la scorciatoia smette di funzionare appena
    /// l'oggetto viene ripulito.
    private let scorciatoiaRapida = GlobalHotKey {
        guard MasterKey.isConfigured else { return } // niente onboarding fatto, niente popup
        QuickAddPanelController.shared.toggle()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        }
        .windowStyle(.hiddenTitleBar) // parete edge-to-edge, senza barra del titolo
        // .contentSize + frame fisso = finestra non ridimensionabile
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // "Nuovo documento" non ha senso per questa app
            CommandGroup(after: .appInfo) {
                Button("Verifica aggiornamenti…") {
                    updaterController.checkForUpdates(nil)
                }
            }
        }
    }
}
