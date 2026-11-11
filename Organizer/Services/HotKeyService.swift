import Carbon.HIToolbox
import Foundation

/// Wählbare globale Tastenkürzel für die Schnellerfassung.
enum HotKeyPreset: String, CaseIterable {
    case controlOptionSpace
    case commandShiftN
    case controlOptionN
    case off

    var title: String {
        switch self {
        case .controlOptionSpace: L("⌃⌥ Leertaste")
        case .commandShiftN: "⇧⌘N"
        case .controlOptionN: "⌃⌥N"
        case .off: L("Aus")
        }
    }

    /// Hinweis, falls das Kürzel anderen Apps etwas wegnimmt.
    var warning: String? {
        switch self {
        case .commandShiftN: L("Im Finder ist ⇧⌘N „Neuer Ordner“ – solange Organizer läuft, öffnet es stattdessen die Schnellerfassung.")
        default: nil
        }
    }

    fileprivate var keyAndModifiers: (key: UInt32, modifiers: UInt32)? {
        switch self {
        case .controlOptionSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .commandShiftN: (UInt32(kVK_ANSI_N), UInt32(cmdKey | shiftKey))
        case .controlOptionN: (UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey))
        case .off: nil
        }
    }
}

/// Systemweites Tastenkürzel über die Carbon-API (funktioniert auch in der Sandbox,
/// ohne Bedienungshilfen-Freigabe).
final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var action: (() -> Void)?

    func register(_ preset: HotKeyPreset) {
        unregister()
        guard let (key, modifiers) = preset.keyAndModifiers else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            // Carbon ruft auf dem Haupt-Thread auf.
            MainActor.assumeIsolated { service.action?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let id = EventHotKeyID(signature: OSType(0x4F52_474E), id: 1) // „ORGN“
        RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
    }
}
