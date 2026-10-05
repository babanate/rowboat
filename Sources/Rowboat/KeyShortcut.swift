import AppKit
import Carbon

/// A key combination: virtual key code plus modifier flags.
struct KeyShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt  // NSEvent.ModifierFlags.rawValue, device-independent bits only

    static let relevantFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantFlags).rawValue
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.relevantFlags) == flags
    }

    /// Modifier mask in Carbon's encoding, for RegisterEventHotKey.
    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var displayString: String {
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }
}

enum KeyNames {
    static let special: [UInt16: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 76: "⌤",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    static func name(for keyCode: UInt16) -> String {
        if let s = special[keyCode] { return s }
        return character(for: keyCode)?.uppercased() ?? "key\(keyCode)"
    }

    /// Unmodified character for a key code in the current keyboard layout.
    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { bytes -> OSStatus in
            let layout = bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
