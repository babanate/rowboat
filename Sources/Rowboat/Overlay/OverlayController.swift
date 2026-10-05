import AppKit

/// Owns one overlay window per screen and renders scenes onto all of them.
final class OverlayController {
    private var windows: [OverlayWindow] = []
    private var flashTimer: Timer?

    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private func ensureWindows() {
        if windows.count == NSScreen.screens.count, zip(windows, NSScreen.screens).allSatisfy({ $0.frame == $1.frame }) { return }
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map(OverlayWindow.init)
    }

    @objc private func screensChanged() {
        let visible = windows.contains { $0.isVisible }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if visible { ensureWindows(); windows.forEach { $0.orderFrontRegardless() } }
    }

    func show(_ scene: OverlayScene) {
        flashTimer?.invalidate()
        ensureWindows()
        for w in windows {
            w.coverScreen()
            w.render(scene)
            if !w.isVisible { w.orderFrontRegardless() }
        }
    }

    func hide() {
        flashTimer?.invalidate()
        windows.forEach { $0.orderOut(nil) }
    }

    /// Shows a message briefly, then hides the overlay.
    func flash(_ message: String, duration: TimeInterval = 0.7) {
        show(OverlayScene(message: message))
        flashTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in self?.hide() }
    }
}
