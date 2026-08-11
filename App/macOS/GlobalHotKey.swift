import Carbon.HIToolbox
import AppKit

/// Scorciatoia globale (funziona anche con Hush in background, da qualunque
/// app): usa le vecchie API Carbon apposta per questo, non un monitor
/// globale della tastiera — quelle spiano OGNI tasto premuto ovunque e
/// macOS chiede il permesso "Controllo accessibilità"; RegisterEventHotKey
/// registra solo LA combinazione che ci interessa, senza permessi da
/// chiedere né tasti altrui da vedere.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onPress: () -> Void

    /// ⌃⌥H — improbabile che collida con scorciatoie di sistema o di terze parti.
    init(keyCode: UInt32 = UInt32(kVK_ANSI_H),
         modifiers: UInt32 = UInt32(controlKey | optionKey),
         onPress: @escaping () -> Void) {
        self.onPress = onPress
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var hotKeyID = EventHotKeyID(signature: OSType(0x48555348), id: 1) // 'HUSH'

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { owner.onPress() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handler { RemoveEventHandler(handler) }
    }
}
