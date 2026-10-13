import Foundation
#if os(macOS)
import Carbon.HIToolbox
#endif

/// Le poche cose regolabili delHush. Stanno nei UserDefaults perché
/// non sono segreti: sono soglie e preferenze, non chiavi.
enum Preferences {
    private static let d = UserDefaults.standard

    private enum Key {
        static let autolockMinutes = "scrigno.pref.autolockMinutes"
        static let clipboardSeconds = "scrigno.pref.clipboardSeconds"
        static let passwordLength = "scrigno.pref.passwordLength"
        static let passwordSymbols = "scrigno.pref.passwordSymbols"
        static let typeAgainDays = "scrigno.pref.typeAgainDays"
        static let vistaClassica = "scrigno.pref.vistaClassica"
        static let vistoAiutoParete = "scrigno.pref.vistoAiutoParete"
        static let mostraDock = "scrigno.pref.mostraDock"
        #if os(macOS)
        static let quickAddKeyCode = "scrigno.pref.hotkey.quickAdd.keyCode"
        static let quickAddModifiers = "scrigno.pref.hotkey.quickAdd.modifiers"
        static let searchKeyCode = "scrigno.pref.hotkey.search.keyCode"
        static let searchModifiers = "scrigno.pref.hotkey.search.modifiers"
        #endif
    }

    /// Registra i valori di partenza: senza, `integer(forKey:)` risponde 0 su
    /// una chiave mai scritta, e 0 qui vorrebbe dire "mai" o "password vuota".
    static func registerDefaults() {
        d.register(defaults: [
            Key.autolockMinutes: 5,
            Key.clipboardSeconds: 30,
            Key.passwordLength: 24,
            Key.passwordSymbols: true,
            Key.typeAgainDays: 7,
            Key.mostraDock: true,
        ])
        #if os(macOS)
        d.register(defaults: [
            // Invertite apposta rispetto ai nomi delle chiavi: ⌘P (la
            // combinazione "naturale", senza tasti extra) ora cerca, non
            // crea — l'azione più frequente vince la scorciatoia più corta.
            Key.quickAddKeyCode: Int(kVK_ANSI_P),
            Key.quickAddModifiers: Int(controlKey | cmdKey),
            Key.searchKeyCode: Int(kVK_ANSI_P),
            Key.searchModifiers: Int(cmdKey),
        ])
        #endif
    }

    /// Minuti d'inattività dopo cui Hush si richiude. 0 = mai.
    static var autolockMinutes: Int {
        get { d.integer(forKey: Key.autolockMinutes) }
        set { d.set(newValue, forKey: Key.autolockMinutes) }
    }

    /// Secondi dopo cui una password copiata sparisce dagli appunti. 0 = mai.
    static var clipboardSeconds: Int {
        get { d.integer(forKey: Key.clipboardSeconds) }
        set { d.set(newValue, forKey: Key.clipboardSeconds) }
    }

    static var passwordLength: Int {
        get { max(8, d.integer(forKey: Key.passwordLength)) }
        set { d.set(newValue, forKey: Key.passwordLength) }
    }

    static var passwordSymbols: Bool {
        get { d.bool(forKey: Key.passwordSymbols) }
        set { d.set(newValue, forKey: Key.passwordSymbols) }
    }

    /// La schermata di prima del rewrite: elenco con barra laterale al
    /// posto della parete 3D. Chiave usata anche da @AppStorage in RootView.
    static var vistaClassica: Bool {
        get { d.bool(forKey: Key.vistaClassica) }
        set { d.set(newValue, forKey: Key.vistaClassica) }
    }

    /// Ogni quanti giorni la master password va comunque digitata a mano.
    /// 0 = mai: si entra sempre col dito, a proprio rischio.
    static var typeAgainDays: Int {
        get { max(0, d.integer(forKey: Key.typeAgainDays)) }
        set { d.set(newValue, forKey: Key.typeAgainDays) }
    }

    /// Il fumetto che spiega come creare il primo cassetto, l'icona e la
    /// prima voce: si vede solo finché la parete è vuota E non l'hai già
    /// chiuso — dopo, anche svuotando tutto, non deve ripresentarsi da solo.
    static var vistoAiutoParete: Bool {
        get { d.bool(forKey: Key.vistoAiutoParete) }
        set { d.set(newValue, forKey: Key.vistoAiutoParete) }
    }

    /// Icona nel Dock, oltre a quella nella menu bar. Attiva di default:
    /// chi non sa cos'è la menu bar deve comunque trovare l'app.
    static var mostraDock: Bool {
        get { d.bool(forKey: Key.mostraDock) }
        set { d.set(newValue, forKey: Key.mostraDock) }
    }

    #if os(macOS)
    /// Tasto + modificatori di una scorciatoia globale, così com'è capita
    /// da Carbon (RegisterEventHotKey vuole proprio queste due cose).
    struct HotKey: Equatable {
        var keyCode: UInt32
        var modifiers: UInt32
    }

    static var quickAddHotKey: HotKey {
        get { HotKey(keyCode: UInt32(d.integer(forKey: Key.quickAddKeyCode)),
                      modifiers: UInt32(d.integer(forKey: Key.quickAddModifiers))) }
        set {
            d.set(Int(newValue.keyCode), forKey: Key.quickAddKeyCode)
            d.set(Int(newValue.modifiers), forKey: Key.quickAddModifiers)
        }
    }

    static var searchHotKey: HotKey {
        get { HotKey(keyCode: UInt32(d.integer(forKey: Key.searchKeyCode)),
                      modifiers: UInt32(d.integer(forKey: Key.searchModifiers))) }
        set {
            d.set(Int(newValue.keyCode), forKey: Key.searchKeyCode)
            d.set(Int(newValue.modifiers), forKey: Key.searchModifiers)
        }
    }
    #endif
}
