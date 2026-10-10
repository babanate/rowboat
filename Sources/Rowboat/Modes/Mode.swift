import AppKit

enum ModeKind: String, CaseIterable {
    case hints, scroll, search, grid
}

/// Services a mode needs from its controller.
protocol ModeHost: AnyObject {
    var overlay: OverlayController { get }
    var settings: Settings { get }
    var app: NSRunningApplication { get }
    /// Ends the current mode: stops key capture and hides the overlay.
    func finish()
}

protocol Mode: AnyObject {
    var kind: ModeKind { get }
    func begin()
    func handle(_ event: KeyEvent)
    func end()
}

extension KeyEvent {
    var clickKind: ClickKind {
        if modifiers.contains(.shift) { return .right }
        if modifiers.contains(.command) { return .command }
        if modifiers.contains(.option) { return .double }
        if modifiers.contains(.control) { return .middle }
        return .left
    }
}
