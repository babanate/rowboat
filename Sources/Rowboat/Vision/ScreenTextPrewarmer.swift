import AppKit

/// Reads the frontmost window off the screen in the background when an app
/// that needs screen text becomes active, and shortly after each click in
/// one, so the next press finds the OCR result cached (~30 ms instead of
/// ~200 ms). Bounded: one pass per trigger, nothing while idle, no
/// periodic polling.
final class ScreenTextPrewarmer {
    static let shared = ScreenTextPrewarmer()
    private var observer: Any?
    private var pending: DispatchWorkItem?

    func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.schedule(app, after: 0.25)
        }
    }

    func wants(_ app: NSRunningApplication) -> Bool {
        let settings = Settings.shared
        guard settings.screenTextFallback, let id = app.bundleIdentifier else { return false }
        return settings.screenTextApps.contains(id) || ScreenTextScanner.shared.appsNeedingText.contains(id)
    }

    /// Schedules one background scan of `app`'s focused window, replacing any pending one.
    func schedule(_ app: NSRunningApplication, after delay: TimeInterval) {
        guard wants(app), ScreenCapture.hasPermission(prompt: false) else { return }
        pending?.cancel()
        let pid = app.processIdentifier
        let item = DispatchWorkItem {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            ElementCollector.ocrQueue.async {
                let appElement = AXElement.application(pid: pid)
                AXUIElementSetMessagingTimeout(appElement.raw, 0.2)
                guard let window = appElement.element(kAXFocusedWindowAttribute), let frame = window.frame else { return }
                let screenBounds = NSScreen.screens.reduce(CGRect.null) { $0.union(ElementCollector.axRect(for: $1)) }
                let result = ScreenTextScanner.shared.scan(frame.intersection(screenBounds))
                Log.ax.info("prewarm: \(result.targets.count) phrases in \(Int(result.elapsed * 1000)) ms\(result.fromCache ? " (unchanged)" : "")")
            }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
