import SwiftUI

@main
struct ScrignoMacApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 720, minHeight: 480)
        }
        .windowStyle(.hiddenTitleBar) // parete edge-to-edge, senza barra del titolo
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {} // "Nuovo documento" non ha senso per questa app
        }
    }
}
