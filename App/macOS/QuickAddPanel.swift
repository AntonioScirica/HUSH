import SwiftUI
import AppKit

/// Mostra QuickAddView come un pannello fluttuante, tipo Spotlight — sopra
/// tutto il resto, richiamabile da qualunque app con ⌃⌥H.
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

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.center()

        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func close() {
        panel?.close()
        panel = nil
    }
}
