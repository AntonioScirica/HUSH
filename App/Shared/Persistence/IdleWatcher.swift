import Foundation
import AppKit

/// Richiude lo scrigno quando lo si lascia lì aperto.
///
/// Guarda tastiera e mouse dentro l'app: ogni evento rimanda la scadenza, e
/// se passa il tempo scelto senza che succeda niente scatta `onIdle`. La
/// sorveglianza è locale (`addLocalMonitorForEvents`), quindi vede solo gli
/// eventi diretti a questa app — quello che serve, e niente di più.
@MainActor
final class IdleWatcher: ObservableObject {
    var onIdle: () -> Void = {}

    private var monitor: Any?
    private var timer: Timer?
    private var lastActivity = Date()

    func start() {
        stop()
        guard Preferences.autolockMinutes > 0 else { return }
        lastActivity = Date()

        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.lastActivity = Date()
            return event   // l'evento prosegue: qui si osserva soltanto
        }

        // un controllo al secondo basta e avanza: la soglia è in minuti
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIdle() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
    }

    private func checkIdle() {
        let limit = TimeInterval(Preferences.autolockMinutes) * 60
        guard limit > 0, Date().timeIntervalSince(lastActivity) >= limit else { return }
        stop()
        onIdle()
    }
}
