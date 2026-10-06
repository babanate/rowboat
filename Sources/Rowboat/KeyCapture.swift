import AppKit
import CoreGraphics

/// A key event delivered while a mode is active.
struct KeyEvent {
    enum Kind { case down, up, flagsChanged }
    let kind: Kind
    let keyCode: UInt16
    let characters: String            // with modifiers applied (e.g. "A")
    let charactersIgnoringModifiers: String
    let modifiers: NSEvent.ModifierFlags
    let isRepeat: Bool

    var isEscape: Bool { keyCode == 53 }
    var isReturn: Bool { keyCode == 36 || keyCode == 76 }
    var isBackspace: Bool { keyCode == 51 }
    var isTab: Bool { keyCode == 48 }
    var isSpace: Bool { keyCode == 49 }
}

/// Session-level event tap that swallows keyboard events while enabled.
/// Installed only while a mode is active, so idle typing is never delayed.
final class KeyCapture {
    typealias Handler = (KeyEvent) -> Void

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: Handler?
    private var reenabledOnce = false
    /// Called when the tap dies and could not be revived; the owner must end the mode.
    var onFailure: (() -> Void)?

    var isActive: Bool { tap != nil }

    func start(handler: @escaping Handler) -> Bool {
        stop()
        self.handler = handler
        reenabledOnce = false
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: KeyCapture.callback, userInfo: selfPtr) else {
            Log.input.error("event tap creation failed (accessibility permission?)")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        handler = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, cgEvent, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(cgEvent) }
        let capture = Unmanaged<KeyCapture>.fromOpaque(userInfo).takeUnretainedValue()
        return capture.handle(type: type, cgEvent: cgEvent)
    }

    private func handle(type: CGEventType, cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if !reenabledOnce, let tap {
                reenabledOnce = true
                Log.input.warning("event tap disabled (\(type.rawValue)); re-enabling once")
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                Log.input.error("event tap disabled again; giving up")
                DispatchQueue.main.async { [weak self] in self?.onFailure?() }
            }
            return Unmanaged.passUnretained(cgEvent)
        case .keyDown, .keyUp, .flagsChanged:
            guard let nsEvent = NSEvent(cgEvent: cgEvent) else { return Unmanaged.passUnretained(cgEvent) }
            let kind: KeyEvent.Kind = type == .keyDown ? .down : (type == .keyUp ? .up : .flagsChanged)
            let isKey = kind != .flagsChanged
            let event = KeyEvent(kind: kind, keyCode: nsEvent.keyCode,
                                 characters: isKey ? (nsEvent.characters ?? "") : "",
                                 charactersIgnoringModifiers: isKey ? (nsEvent.charactersIgnoringModifiers ?? "") : "",
                                 modifiers: nsEvent.modifierFlags.intersection(KeyShortcut.relevantFlags),
                                 isRepeat: isKey ? nsEvent.isARepeat : false)
            handler?(event)
            // Swallow key-downs. Key-ups and modifier changes pass through so
            // the system's view of what is held (hot keys, modifier state) stays
            // consistent; a stray key-up is harmless to the app underneath.
            return kind == .down ? nil : Unmanaged.passUnretained(cgEvent)
        default:
            return Unmanaged.passUnretained(cgEvent)
        }
    }
}
