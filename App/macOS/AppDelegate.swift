import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Le Impostazioni la mandano dopo aver salvato una nuova combinazione:
    /// l'AppDelegate la ascolta per ri-registrare le scorciatoie globali.
    static let scorciatoieHushCambiate = Notification.Name("scorciatoieHushCambiate")
    /// Mandate da `HotKeyRecorder` mentre aspetta la pressione dei tasti:
    /// senza sospendere quelle vecchie, premere di nuovo la combinazione
    /// che si sta per sostituire la fa scattare (apre il popup) invece di
    /// lasciarla catturare dal registratore.
    static let scorciatoieHushSospendi = Notification.Name("scorciatoieHushSospendi")
    static let scorciatoieHushRiprendi = Notification.Name("scorciatoieHushRiprendi")
}

/// Registra la scorciatoia globale qui, non come stored property della App:
/// a quel punto (init della struct, prima ancora che l'app sia avviata per
/// davvero) l'event target di Carbon non è ancora pronto e RegisterEventHotKey
/// falliva in silenzio — la scorciatoia sembrava "non fare niente".
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var scorciatoiaRapida: GlobalHotKey?
    private var scorciatoiaRicerca: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private weak var finestraPrincipale: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults() // prima di leggere mostraDock (e le scorciatoie) qui sotto

        registraScorciatoie()
        NotificationCenter.default.addObserver(
            forName: .scorciatoieHushCambiate, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.registraScorciatoie() } }
        NotificationCenter.default.addObserver(
            forName: .scorciatoieHushSospendi, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.scorciatoiaRapida = nil; self?.scorciatoiaRicerca = nil } }
        NotificationCenter.default.addObserver(
            forName: .scorciatoieHushRiprendi, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.registraScorciatoie() } }

        // Se è passata una settimana dall'ultimo backup su Drive, parte da
        // sé — non costa niente controllare se non è ancora il momento.
        if !DemoMode.attivo { Task { await GoogleDriveBackup.backupIfDue() } }

        setupStatusItem()
        NSApp.setActivationPolicy(Preferences.mostraDock ? .regular : .accessory)

        // La finestra non si chiude mai per davvero — la chiusura la
        // nasconde soltanto, così il bridge locale (e quindi l'estensione)
        // resta raggiungibile finché Hush è sbloccato, senza dover
        // riaprire l'app da zero ogni volta.
        if let window = NSApp.windows.first {
            finestraPrincipale = window
            window.delegate = self
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    /// Assegnare una NUOVA `GlobalHotKey` sostituisce quella vecchia: il suo
    /// `deinit` deregistra da Carbon da sé, quindi qui basta ricrearle con i
    /// valori appena salvati — niente deregistrazione esplicita da scrivere.
    @MainActor
    private func registraScorciatoie() {
        scorciatoiaRapida = GlobalHotKey(keyCode: Preferences.quickAddHotKey.keyCode,
                                          modifiers: Preferences.quickAddHotKey.modifiers) {
            guard MasterKey.isConfigured else { return } // niente onboarding fatto, niente popup
            QuickAddPanelController.shared.toggle()
        }
        // Cerca una voce e copia la password, senza passare da Comandi
        // Rapidi/Siri — quella strada si è rivelata inaffidabile (l'azione
        // non sempre viene indicizzata dal sistema).
        scorciatoiaRicerca = GlobalHotKey(keyCode: Preferences.searchHotKey.keyCode,
                                           modifiers: Preferences.searchHotKey.modifiers) {
            guard MasterKey.isConfigured else { return }
            SearchPanelController.shared.toggle()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Hush")
        item.button?.action = #selector(toggleFinestra)
        item.button?.target = self
        statusItem = item
    }

    @objc private func toggleFinestra() {
        guard let window = finestraPrincipale ?? NSApp.windows.first else { return }
        finestraPrincipale = window
        if window.isVisible {
            window.orderOut(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
