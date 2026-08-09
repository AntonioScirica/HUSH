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
    private var observers: [NSObjectProtocol] = []
    private var lastActivity = Date()

    func start() {
        stop()
        // Lo spegnimento dello schermo richiude comunque, anche con il conto
        // alla rovescia disattivato: quello è "non chiudere mentre lavoro",
        // non "lascia aperto quando me ne vado".
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

        // Schermo bloccato o Mac addormentato: si richiude subito, senza
        // aspettare il conto alla rovescia. Chi si alza dalla scrivania e
        // blocca lo schermo si aspetta che lo scrigno sia già chiuso, non che
        // lo diventi cinque minuti dopo.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.lockNow() }
                }
            )
        }
        // il blocco schermo non ha una notifica in NSWorkspace: passa dal
        // centro notifiche distribuito del sistema
        let distributed = DistributedNotificationCenter.default()
        observers.append(
            distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                    object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.lockNow() }
            }
        )
    }

    private func lockNow() {
        guard timer != nil else { return }   // già chiuso
        stop()
        onIdle()
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        observers = []
    }

    private func checkIdle() {
        let limit = TimeInterval(Preferences.autolockMinutes) * 60
        guard limit > 0, Date().timeIntervalSince(lastActivity) >= limit else { return }
        stop()
        onIdle()
    }
}
