import SwiftUI

@main
struct ScrignoMacApp: App {
    /// Finestra di misura fissa: la parete, la porta del caveau e le schede
    /// che si agganciano alle cartelle sono tarate su questo formato.
    /// È la misura del CONTENUTO: la finestra ci aggiunge sopra la barra del
    /// titolo nascosta (32 pt), e viene fuori il 829×612 di prima.
    private static let windowSize = CGSize(width: 829, height: 580)

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
        }
    }
}
