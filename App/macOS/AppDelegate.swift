import AppKit
import Carbon.HIToolbox

/// Registra la scorciatoia globale qui, non come stored property della App:
/// a quel punto (init della struct, prima ancora che l'app sia avviata per
/// davvero) l'event target di Carbon non è ancora pronto e RegisterEventHotKey
/// falliva in silenzio — la scorciatoia sembrava "non fare niente".
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var scorciatoiaRapida: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌘P: a scelta di chi usa l'app, sapendo che intercetta la Stampa
        // di sistema in ogni altra app finché Hush resta aperto.
        scorciatoiaRapida = GlobalHotKey(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey)) {
            guard MasterKey.isConfigured else { return } // niente onboarding fatto, niente popup
            QuickAddPanelController.shared.toggle()
        }

        // Se è passata una settimana dall'ultimo backup su Drive, parte da
        // sé — non costa niente controllare se non è ancora il momento.
        Task { await GoogleDriveBackup.backupIfDue() }
    }
}
