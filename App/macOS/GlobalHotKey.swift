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
    /// Con più scorciatoie attive i handler Carbon si mettono in coda
    /// sull'app intera, e l'ultimo installato riceve OGNI pressione: senza
    /// un id univoco da confrontare, ⌘P finiva nel handler di ⌃⌘P (che
    /// rispondeva "gestito" e apriva la ricerca al posto del QuickAdd).
    private let hotKeyID: EventHotKeyID
    private static var prossimoID: UInt32 = 1

    init(keyCode: UInt32 = UInt32(kVK_ANSI_H),
         modifiers: UInt32 = UInt32(controlKey | optionKey),
         onPress: @escaping () -> Void) {
        self.onPress = onPress
        self.hotKeyID = EventHotKeyID(signature: OSType(0x48555348), id: Self.prossimoID) // 'HUSH'
        Self.prossimoID += 1
        register(keyCode: keyCode, modifiers: modifiers)
    }

    private func register(keyCode: UInt32, modifiers: UInt32) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            // Di chi è questa pressione? Se non è la NOSTRA combinazione,
            // si passa la mano al handler successivo nella coda.
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.id == owner.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
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
