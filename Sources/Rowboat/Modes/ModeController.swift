import AppKit

/// Runs at most one mode at a time and owns the shared overlay and key capture.
final class ModeController: ModeHost {
    let overlay = OverlayController()
    let settings = Settings.shared
    private let keyCapture = KeyCapture()
    private(set) var current: Mode?
    private(set) var app: NSRunningApplication = .current
    private var deactivationObserver: Any?

    init() {
        keyCapture.onFailure = { [weak self] in
            Log.mode.error("key capture failed; ending mode")
            self?.finish()
        }
        deactivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, self.current != nil,
                  let activated = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activated.processIdentifier != self.app.processIdentifier,
                  activated.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Log.mode.info("frontmost app changed; ending mode")
            self.finish()
        }
    }

    /// The mode a key event would trigger, if it matches a configured shortcut.
    private func shortcutKind(for event: KeyEvent) -> ModeKind? {
        let pairs: [(KeyShortcut?, ModeKind)] = [(settings.hintsShortcut, .hints), (settings.scrollShortcut, .scroll), (settings.searchShortcut, .search)]
        for (shortcut, kind) in pairs {
            if let s = shortcut, s.keyCode == event.keyCode, event.modifiers == s.flags { return kind }
        }
        return nil
    }

    func activate(_ kind: ModeKind) {
        if let current {
            let same = current.kind == kind
            Log.mode.info("re-press while \(current.kind.rawValue) active: \(same ? "ending" : "switching")")
            finish()
            if same { return }
        }
        guard let front = NSWorkspace.shared.frontmostApplication else { Log.mode.warning("no frontmost app"); return }
        if front.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            // Our own settings window is frontmost; nothing to label there.
            Log.mode.info("Rowboat itself is frontmost; ignoring")
            return
        }
        if settings.isExcluded(bundleIdentifier: front.bundleIdentifier) {
            Log.mode.info("\(front.bundleIdentifier ?? "?") is excluded")
            return
        }
        guard Permissions.accessibilityTrusted(prompt: true) else {
            overlay.flash("Rowboat needs Accessibility access", duration: 1.5)
            return
        }
        app = front
        // While a mode is open the tap owns the keyboard, so the hot key cannot
        // fire; recognise the shortcuts here so a re-press still toggles.
        guard keyCapture.start(handler: { [weak self] event in
            guard let self else { return }
            if event.kind == .down, !event.isRepeat, let kind = self.shortcutKind(for: event) {
                self.activate(kind)
                return
            }
            self.current?.handle(event)
        }) else {
            overlay.flash("Could not capture keyboard", duration: 1.5)
            return
        }
        let mode: Mode
        switch kind {
        case .hints: mode = HintsMode(host: self, searchable: false)
        case .search: mode = HintsMode(host: self, searchable: true)
        case .scroll: mode = ScrollMode(host: self)
        }
        current = mode
        Log.mode.info("begin \(kind.rawValue) in \(front.bundleIdentifier ?? "?")")
        mode.begin()
    }

    func finish() {
        guard let mode = current else { return }
        current = nil
        mode.end()
        keyCapture.stop()
        overlay.hide()
        Log.mode.info("end \(mode.kind.rawValue)")
    }
}
