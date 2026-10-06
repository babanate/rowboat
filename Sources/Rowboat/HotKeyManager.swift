import AppKit
import Carbon

/// Global shortcuts via Carbon hot keys. Carbon hot keys add no latency to
/// ordinary typing, unlike a permanent event tap.
final class HotKeyManager {
    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var nextID: UInt32 = 1
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5257_4254 // "RWBT"

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            Log.input.info("hot key \(hotKeyID.id) fired")
            manager.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    deinit {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Registers a shortcut. Returns false when the system refuses it, which
    /// usually means another app (Homerow, say) already owns that combination.
    @discardableResult
    func register(_ shortcut: KeyShortcut, handler: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         EventHotKeyID(signature: Self.signature, id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.input.error("RegisterEventHotKey \(shortcut.displayString) failed: \(status)")
            return false
        }
        handlers[id] = handler
        refs[id] = ref
        return true
    }

    func unregisterAll() {
        for (_, ref) in refs { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }
}
