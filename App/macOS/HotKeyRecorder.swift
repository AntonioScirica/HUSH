import SwiftUI
import Carbon.HIToolbox

/// Le scorciatoie globali sono salvate coi valori "alla Carbon"
/// (RegisterEventHotKey le vuole così): risalire da lì a un simbolo
/// leggibile serve solo per mostrarlo, mai per registrare la scorciatoia.
enum HotKeyDisplay {
    static func testo(_ combo: Preferences.HotKey) -> String {
        var s = ""
        if combo.modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if combo.modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if combo.modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if combo.modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += carattere(perKeyCode: combo.keyCode)
        return s
    }

    /// Solo le poche usabili qui: lettere, numeri, spazio. Non serve una
    /// tabella completa, le scorciatoie globali sensate stanno tutte lì.
    private static func carattere(perKeyCode keyCode: UInt32) -> String {
        let lettere: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9", UInt32(kVK_Space): "Spazio",
        ]
        return lettere[keyCode] ?? "?"
    }
}

/// Cattura la prossima combinazione premuta e la offre come `Preferences.HotKey`.
/// A riposo mostra quella attuale; premuto, aspetta un tasto vero (con
/// almeno un modificatore, altrimenti "P" da solo intercetterebbe ogni "p"
/// digitato ovunque).
struct HotKeyRecorder: View {
    @Binding var combo: Preferences.HotKey
    let onChanged: () -> Void

    @State private var registrando = false
    @State private var monitor: Any?
    @State private var errore: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if registrando { fermaRegistrazione() } else { avviaRegistrazione() }
            } label: {
                HStack {
                    Text(registrando ? "Premi la combinazione…" : HotKeyDisplay.testo(combo))
                        .font(Theme.mono(12, .semibold))
                        .foregroundStyle(registrando ? Theme.inkSoft : Theme.ink)
                    Spacer(minLength: 0)
                    if registrando {
                        Text("Esc per annullare")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(registrando ? Theme.yellow.opacity(0.3) : Theme.paperRaised)
                .overlay(Rectangle().strokeBorder(registrando ? Theme.ink : Theme.line, lineWidth: 1.1))
            }
            .buttonStyle(.plain)

            if let errore {
                Text(errore).font(Theme.mono(9)).foregroundStyle(Theme.danger)
            }
        }
        .onDisappear { fermaRegistrazione() }
    }

    private func avviaRegistrazione() {
        errore = nil
        registrando = true
        // Altrimenti ripremere la combinazione attuale la fa scattare (apre
        // il popup) invece di lasciarla catturare qui sotto.
        NotificationCenter.default.post(name: .scorciatoieHushSospendi, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            defer { fermaRegistrazione() }
            if event.keyCode == UInt32(kVK_Escape) { return nil } // annulla, non salva

            var modificatori: UInt32 = 0
            if event.modifierFlags.contains(.control) { modificatori |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option)  { modificatori |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift)   { modificatori |= UInt32(shiftKey) }
            if event.modifierFlags.contains(.command) { modificatori |= UInt32(cmdKey) }

            guard modificatori != 0 else {
                errore = "Serve almeno un tasto modificatore (⌘, ⌃, ⌥ o ⇧)."
                return nil
            }

            combo = Preferences.HotKey(keyCode: UInt32(event.keyCode), modifiers: modificatori)
            onChanged()
            return nil // consumato: non deve arrivare a nessun'altra app
        }
    }

    private func fermaRegistrazione() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if registrando {
            registrando = false
            // Rilegge da Preferences: se è stata appena salvata una nuova
            // combinazione la trova già lì (onChanged gira prima di questo,
            // vedi il defer sopra), altrimenti torna quella di prima.
            NotificationCenter.default.post(name: .scorciatoieHushRiprendi, object: nil)
        }
    }
}
