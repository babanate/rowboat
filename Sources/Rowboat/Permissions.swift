import ApplicationServices

enum Permissions {
    /// Whether this process may use the Accessibility API. With `prompt`,
    /// macOS shows its own dialog pointing at System Settings.
    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
