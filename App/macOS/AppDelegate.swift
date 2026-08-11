import AppKit

/// Registra la scorciatoia globale qui, non come stored property della App:
/// a quel punto (init della struct, prima ancora che l'app sia avviata per
/// davvero) l'event target di Carbon non è ancora pronto e RegisterEventHotKey
/// falliva in silenzio — la scorciatoia sembrava "non fare niente".
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var scorciatoiaRapida: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        scorciatoiaRapida = GlobalHotKey {
            guard MasterKey.isConfigured else { return } // niente onboarding fatto, niente popup
            QuickAddPanelController.shared.toggle()
        }
    }
}
