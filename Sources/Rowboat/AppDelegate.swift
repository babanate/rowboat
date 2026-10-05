import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let modes = ModeController()
    private var hotKeys = HotKeyManager()
    private var statusItem: StatusItemController?
    private var settingsWindow: SettingsWindowController?
    private var settingsObserver: AnyCancellable?
    private var trustTimer: Timer?
    private var enabler: AccessibilityEnabler?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }
        Log.app.info("Rowboat starting")
        statusItem = StatusItemController(modes: modes) { [weak self] in self?.showSettings() }
        registerHotKeys()
        if Permissions.accessibilityTrusted(prompt: false) { enabler = AccessibilityEnabler() }

        settingsObserver = Settings.shared.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.registerHotKeys()
                self?.statusItem?.update()
            }

        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(activateFromNotification(_:)), name: CLI.activateNotification, object: nil)
        center.addObserver(self, selector: #selector(showSettingsFromNotification), name: CLI.settingsNotification, object: nil)

        if !Permissions.accessibilityTrusted(prompt: true) {
            Log.app.warning("accessibility not granted yet")
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                if Permissions.accessibilityTrusted(prompt: false) {
                    timer.invalidate()
                    Log.app.info("accessibility granted")
                    self?.registerHotKeys()
                    self?.enabler = AccessibilityEnabler()
                }
            }
        }
    }

    /// A second launch (e.g. from Finder while the menu bar icon is hidden)
    /// asks the running instance to show settings and exits.
    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(CLI.settingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
        NSApp.terminate(nil)
        return true
    }

    private func registerHotKeys() {
        hotKeys.unregisterAll()
        let s = Settings.shared
        hotKeys.register(s.hintsShortcut) { [weak self] in self?.modes.activate(.hints) }
        hotKeys.register(s.scrollShortcut) { [weak self] in self?.modes.activate(.scroll) }
        hotKeys.register(s.searchShortcut) { [weak self] in self?.modes.activate(.search) }
    }

    @objc private func activateFromNotification(_ note: Notification) {
        guard let raw = note.userInfo?["mode"] as? String, let kind = ModeKind(rawValue: raw) else { return }
        modes.activate(kind)
    }

    @objc private func showSettingsFromNotification() { showSettings() }

    func showSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
}
