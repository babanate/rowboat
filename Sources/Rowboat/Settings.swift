import AppKit
import Combine
import ServiceManagement

/// User settings, backed by UserDefaults. Observe `objectWillChange` for updates.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults: UserDefaults
    private init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    enum Key: String, CaseIterable {
        case hintsShortcut, scrollShortcut, searchShortcut
        case labelCharacters
        case excludedBundleIdentifiers
        case enableChromiumAccessibility
        case arrowKeysScroll
        case scrollPixelsPerSecond
        case dashMultiplier
        case scrollAutoDeactivateSeconds
        case showMenuBarIcon
        case warpCursorInScrollMode
        case restoreCursorAfterClick
    }

    // Defaults mirror Homerow's so switching is painless.
    static let defaultHintsShortcut = KeyShortcut(keyCode: 49, modifiers: .shift)            // ⇧Space
    static let defaultScrollShortcut = KeyShortcut(keyCode: 38, modifiers: [.shift, .command]) // ⇧⌘J
    static let defaultSearchShortcut = KeyShortcut(keyCode: 44, modifiers: .shift)           // ⇧/
    static let defaultLabelCharacters = "asdfjklghqwertyuiopzxcvbnm"
    /// WebKit browsers expose their page only after AXEnhancedUserInterface is set.
    static let webKitBundlePrefixes = ["com.apple.Safari", "com.apple.SafariTechnologyPreview", "org.webkit"]
    static let chromiumBundlePrefixes = [
        "com.google.Chrome", "org.chromium", "com.brave.Browser", "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi", "company.thebrowser.Browser", "com.operasoftware.Opera",
    ]

    var hintsShortcut: KeyShortcut {
        get { shortcut(.hintsShortcut) ?? Self.defaultHintsShortcut }
        set { setShortcut(newValue, .hintsShortcut) }
    }
    var scrollShortcut: KeyShortcut {
        get { shortcut(.scrollShortcut) ?? Self.defaultScrollShortcut }
        set { setShortcut(newValue, .scrollShortcut) }
    }
    var searchShortcut: KeyShortcut {
        get { shortcut(.searchShortcut) ?? Self.defaultSearchShortcut }
        set { setShortcut(newValue, .searchShortcut) }
    }
    var labelCharacters: String {
        get { defaults.string(forKey: Key.labelCharacters.rawValue).flatMap { $0.count >= 2 ? $0 : nil } ?? Self.defaultLabelCharacters }
        set { set(newValue, .labelCharacters) }
    }
    var excludedBundleIdentifiers: [String] {
        get { defaults.stringArray(forKey: Key.excludedBundleIdentifiers.rawValue) ?? [] }
        set { set(newValue, .excludedBundleIdentifiers) }
    }
    var enableChromiumAccessibility: Bool {
        get { bool(.enableChromiumAccessibility, default: true) }
        set { set(newValue, .enableChromiumAccessibility) }
    }
    var arrowKeysScroll: Bool {
        get { bool(.arrowKeysScroll, default: true) }
        set { set(newValue, .arrowKeysScroll) }
    }
    var scrollPixelsPerSecond: Double {
        get { double(.scrollPixelsPerSecond, default: 1400) }
        set { set(newValue, .scrollPixelsPerSecond) }
    }
    var dashMultiplier: Double {
        get { double(.dashMultiplier, default: 3) }
        set { set(newValue, .dashMultiplier) }
    }
    /// 0 disables auto-deactivation.
    var scrollAutoDeactivateSeconds: Double {
        get { double(.scrollAutoDeactivateSeconds, default: 0) }
        set { set(newValue, .scrollAutoDeactivateSeconds) }
    }
    var showMenuBarIcon: Bool {
        get { bool(.showMenuBarIcon, default: true) }
        set { set(newValue, .showMenuBarIcon) }
    }
    var warpCursorInScrollMode: Bool {
        get { bool(.warpCursorInScrollMode, default: true) }
        set { set(newValue, .warpCursorInScrollMode) }
    }

    var restoreCursorAfterClick: Bool {
        get { bool(.restoreCursorAfterClick, default: false) }
        set { set(newValue, .restoreCursorAfterClick) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.app.error("launch at login: \(error.localizedDescription)")
            }
        }
    }

    func isExcluded(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return excludedBundleIdentifiers.contains(id)
    }

    func isWebKitBrowser(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return Self.webKitBundlePrefixes.contains { id.hasPrefix($0) }
    }

    func isChromium(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return Self.chromiumBundlePrefixes.contains { id.hasPrefix($0) }
    }

    // MARK: storage helpers

    private func shortcut(_ key: Key) -> KeyShortcut? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(KeyShortcut.self, from: data)
    }
    private func setShortcut(_ value: KeyShortcut, _ key: Key) {
        objectWillChange.send()
        defaults.set(try? JSONEncoder().encode(value), forKey: key.rawValue)
    }
    private func bool(_ key: Key, default d: Bool) -> Bool {
        defaults.object(forKey: key.rawValue) == nil ? d : defaults.bool(forKey: key.rawValue)
    }
    private func double(_ key: Key, default d: Double) -> Double {
        defaults.object(forKey: key.rawValue) == nil ? d : defaults.double(forKey: key.rawValue)
    }
    private func set(_ value: Any, _ key: Key) {
        objectWillChange.send()
        defaults.set(value, forKey: key.rawValue)
    }
}
