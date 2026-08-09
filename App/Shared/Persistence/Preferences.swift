import Foundation

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
        ])
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
}
