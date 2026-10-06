import AppKit
import ApplicationServices

enum ClickKind {
    case left, right, command, double, middle
}

/// Performs clicks. Prefers AXPress for plain clicks because it reaches
/// elements covered by other views; falls back to synthetic mouse events.
enum Clicker {
    static func click(_ target: HintTarget, kind: ClickKind, raise: Bool = false) {
        if raise { raiseWindow(of: target) }
        if kind == .left, target.supportsPress, let element = target.element {
            let err = element.perform(kAXPressAction)
            if err == .success {
                Log.mode.info("AXPress on \(target.role) '\(target.displayName)'")
                return
            }
            Log.mode.warning("AXPress failed (\(err.rawValue)); falling back to synthetic click")
        }
        synthesizeClick(at: target.center, kind: kind)
    }

    /// Brings the target's app and window to the front, so a synthetic click
    /// lands as a click and not as a mere activation.
    static func raiseWindow(of target: HintTarget) {
        if target.pid > 0, let app = NSRunningApplication(processIdentifier: target.pid) {
            app.activate()
        }
        if let element = target.element, let window = element.element(kAXWindowAttribute) {
            window.perform("AXRaise")
        }
        usleep(90_000)
    }

    /// Posts a mouse click at `point` (AX top-left coordinates). The cursor is
    /// moved there first so hover states update, then restored.
    static func synthesizeClick(at point: CGPoint, kind: ClickKind) {
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .combinedSessionState)
        var flags: CGEventFlags = []
        var down = CGEventType.leftMouseDown, up = CGEventType.leftMouseUp, button = CGMouseButton.left
        switch kind {
        case .left, .double: break
        case .command: flags = .maskCommand
        case .right: down = .rightMouseDown; up = .rightMouseUp; button = .right
        case .middle: down = .otherMouseDown; up = .otherMouseUp; button = .center
        }
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        let clicks = kind == .double ? 2 : 1
        for n in 1...clicks {
            for type in [down, up] {
                guard let e = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { continue }
                e.flags = flags
                e.setIntegerValueField(.mouseEventClickState, value: Int64(n))
                e.post(tap: .cghidEventTap)
            }
        }
        Log.mode.info("synthetic \(String(describing: kind)) click at \(Int(point.x)),\(Int(point.y))")
        if let original, Settings.shared.restoreCursorAfterClick {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                CGWarpMouseCursorPosition(original)
            }
        }
    }

    /// Scrolls by pixel deltas at a point. Positive dy scrolls content up (wheel down).
    static func scroll(dx: Double, dy: Double, at point: CGPoint) {
        guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                              wheel1: Int32(-dy.rounded()), wheel2: Int32(-dx.rounded()), wheel3: 0) else { return }
        e.location = point
        e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        e.post(tap: .cghidEventTap)
    }
}
