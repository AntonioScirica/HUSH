import SwiftUI
import AppKit

/// Stessa storia di `QuickAddPanel`: serve l'override per accettare la
/// tastiera pur restando `.nonactivatingPanel`.
private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Pannello flottante per cercare una voce e copiarne la password, tipo
/// Spotlight — richiamabile da qualunque app con ⌃⌘P. Stessa meccanica di
/// `QuickAddPanelController`: pannello non attivante, sopra tutto, anche
/// sopra le app a schermo intero.
///
/// A differenza del QuickAdd, questo pannello è trasparente e senza bordo
/// proprio: è la vista SwiftUI dentro a disegnarsi la barra di ricerca (e,
/// quando ci sono risultati, il cartoncino sotto) — così sembra Spotlight,
/// non un riquadro pieno che occupa tutto lo schermo.
@MainActor
final class SearchPanelController {
    static let shared = SearchPanelController()
    private init() {}

    private var panel: NSPanel?
    private var osservatoreFuoco: NSObjectProtocol?
    private static let width: CGFloat = 560
    /// Altezza FISSA, mai ridimensionata: barra + il massimo dei 5
    /// risultati possibili. Ridimensionare l'NSPanel a ogni tasto premuto
    /// era ballerino — qui la finestra è sempre questa misura, e sotto la
    /// barra resta solo spazio trasparente finché SwiftUI non ci disegna
    /// dentro il cartoncino dei risultati.
    private static let altezzaMassima: CGFloat = 54 + 10 + 5 * 56 + 12

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            open()
        }
    }

    private func open() {
        let hosting = NSHostingController(rootView: SearchPasswordView(
            onDone: { [weak self] in self?.close() },
            onAutenticato: { [weak self] in self?.osservaFuoco() }
        ))
        hosting.sizingOptions = []

        let panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.altezzaMassima),
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
        // Sfondo del pannello invisibile: quel che si vede è solo quel che
        // SwiftUI disegna (barra + cartoncino), non un riquadro pieno.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentViewController = hosting
        panel.setContentSize(NSSize(width: Self.width, height: Self.altezzaMassima))
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.center()
        // Il pannello è a misura fissa con la barra in CIMA e sotto solo
        // spazio trasparente per i risultati: centrare il pannello
        // metterebbe la barra ben sopra il centro. Va centrata LEI — il
        // pannello si sposta in giù di quel tanto che porta il centro
        // della barra (10 di padding + metà dei suoi 54) al centro schermo.
        if let screen = panel.screen ?? NSScreen.main, let contenuto = panel.contentView {
            // Niente conti a mano su titlebar e frame (due tentativi, due
            // misure sbagliate): si parte dalla posizione REALE della
            // contentView dopo center() e si sposta la finestra del delta
            // che porta il centro della barra (10 di padding + metà dei
            // suoi 54, dalla cima del contenuto) al centro esatto dello
            // schermo, in orizzontale e in verticale.
            // La titlebar, pur trasparente, crea una safe area in alto e
            // NSHostingController ci spinge sotto il contenuto SwiftUI: la
            // barra non parte dalla cima della contentView ma dall'inset.
            let cimaContenuto = panel.frame.minY + contenuto.frame.maxY - contenuto.safeAreaInsets.top
            let centroBarra = cimaContenuto - (10 + 54 / 2)
            let x = screen.frame.midX - panel.frame.width / 2
            let y = panel.frame.minY + (screen.frame.midY - centroBarra)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        // L'osservatore parte solo a Touch ID finito (vedi onAutenticato
        // sopra): il pannello del sistema per l'autenticazione ruba lui
        // stesso il fuoco, e se l'osservatore fosse già attivo lo
        // scambierebbe per un click fuori, chiudendo tutto a metà.
    }

    /// Un click fuori dal pannello lo chiude, come Spotlight: perde lo
    /// stato di "key window" appena il fuoco passa altrove.
    ///
    /// Il pannello di sistema di Touch ID si porta via lui la "key window":
    /// chiuso il suo, il fuoco non torna da solo al nostro — il campo di
    /// testo restava sotto un cursore che non lampeggiava, perché nessuna
    /// finestra vera aveva davvero la tastiera anche se SwiftUI pensava di
    /// averci messo il focus. Va ripresa a mano.
    private func osservaFuoco() {
        guard let panel else { return }
        panel.makeKeyAndOrderFront(nil)
        guard osservatoreFuoco == nil else { return }
        osservatoreFuoco = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in self?.close() }
    }

    private func close() {
        if let osservatoreFuoco { NotificationCenter.default.removeObserver(osservatoreFuoco) }
        osservatoreFuoco = nil
        panel?.close()
        panel = nil
    }
}
