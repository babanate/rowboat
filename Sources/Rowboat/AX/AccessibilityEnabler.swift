import AppKit

/// Asks Chromium, Electron and WebKit apps to build their accessibility trees
/// ahead of time, at Rowboat start and whenever such an app launches. Without
/// this the first activation in a freshly launched Electron app finds an
/// empty page; Chromium builds the tree asynchronously after the first request.
final class AccessibilityEnabler {
    private var observer: Any?

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // Give the app a few seconds to create its windows before asking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.enable(app) }
        }
        enableRunningApps()
    }

    func enableRunningApps() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            enable(app)
        }
    }

    static func qualifies(_ app: NSRunningApplication) -> Bool {
        let settings = Settings.shared
        if settings.isWebKitBrowser(bundleIdentifier: app.bundleIdentifier) { return true }
        guard settings.enableChromiumAccessibility else { return false }
        return settings.isChromium(bundleIdentifier: app.bundleIdentifier) || ElectronDetector.isElectron(app)
    }

    func enable(_ app: NSRunningApplication) {
        guard Self.qualifies(app), !app.isTerminated else { return }
        let pid = app.processIdentifier
        let name = app.bundleIdentifier ?? "?"
        ElementCollector.queue.async {
            let element = AXElement.application(pid: pid)
            element.set("AXEnhancedUserInterface", true)
            element.set("AXManualAccessibility", true)
            Log.ax.info("enhanced accessibility requested for \(name)")
        }
    }
}
