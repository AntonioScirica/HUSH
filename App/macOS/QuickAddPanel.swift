import SwiftUI
import AppKit

/// Pannello che accetta la tastiera pur essendo `.nonactivatingPanel`:
/// senza questo override i campi di testo non riceverebbero un tasto.
private final class QuickAddPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Mostra QuickAddView come un pannello fluttuante, tipo Spotlight — sopra
/// tutto il resto, richiamabile da qualunque app con ⌘P.
@MainActor
final class QuickAddPanelController {
    static let shared = QuickAddPanelController()
    private init() {}

    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let hosting = NSHostingController(rootView: QuickAddView(onDone: { [weak self] in self?.close() }))
        // Misura decisa dal pannello, MAI dai constraint di SwiftUI: con le
        // sizingOptions di default NSHostingView ridimensiona la finestra da
        // dentro updateConstraints, e AppKit crasha per re-entrancy
        // (_postWindowNeedsUpdateConstraints) appena la vista cambia passo.
        hosting.sizingOptions = []

        // .nonactivatingPanel è la chiave del funzionamento sopra le app a
        // schermo intero: attivare Hush (NSApp.activate) porta al SUO Space,
        // e macOS esce dal pieno schermo invece di sovrapporsi. Un pannello
        // non attivante lascia davanti l'app corrente e ci si appoggia sopra.
        let panel = QuickAddPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 500),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .init(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.animationBehavior = .none
        panel.contentViewController = hosting
        // Assegnare il contentViewController restringe la finestra alla
        // misura intrinseca della vista (che con sizingOptions vuote è
        // minuscola): la misura vera va rimessa DOPO, e poi si centra.
        panel.setContentSize(NSSize(width: 460, height: 500))
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.center()

        self.panel = panel
        // niente NSApp.activate: vedi sopra, farebbe uscire dal pieno schermo
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.close()
        panel = nil
    }
}
