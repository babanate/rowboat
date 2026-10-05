import AppKit

/// Keyboard scrolling of the labelled scroll areas in the frontmost window.
final class ScrollMode: Mode {
    let kind: ModeKind = .scroll
    private unowned let host: ModeHost
    private var areas: [ScrollArea] = []
    private var selected = 0
    private var held: Set<Direction> = []
    private var shiftHeld = false
    private var gPending = false
    private var ticker: Timer?
    private var idleTimer: Timer?
    private var originalCursor: CGPoint?
    private var ended = false

    enum Direction: Hashable { case up, down, left, right }

    init(host: ModeHost) { self.host = host }

    func begin() {
        ScrollAreaCollector.collect(app: host.app) { [weak self] areas in
            guard let self, !self.ended else { return }
            if areas.isEmpty {
                self.host.overlay.flash("No scroll areas")
                self.host.finish()
                return
            }
            self.areas = areas
            let mouse = Self.axMouseLocation()
            self.selected = areas.firstIndex { $0.frame.contains(mouse) } ?? 0
            self.select(self.selected)
            self.resetIdleTimer()
        }
    }

    private func select(_ index: Int) {
        selected = index
        if host.settings.warpCursorInScrollMode {
            if originalCursor == nil { originalCursor = Self.axMouseLocation() }
            CGWarpMouseCursorPosition(areas[index].center)
        }
        render()
    }

    func handle(_ event: KeyEvent) {
        if event.kind == .flagsChanged {
            shiftHeld = event.modifiers.contains(.shift)
            return
        }
        guard !areas.isEmpty else { return }
        let key = event.charactersIgnoringModifiers.lowercased()
        let direction = direction(for: event, key: key)
        if event.kind == .up {
            if let d = direction { held.remove(d); updateTicker() }
            return
        }
        resetIdleTimer()
        if event.isEscape || event.isReturn { host.finish(); return }
        if let d = direction {
            held.insert(d)
            updateTicker()
            return
        }
        if event.isRepeat { return }
        if let digit = Int(key), digit >= 1, digit <= areas.count { select(digit - 1); return }
        if event.isTab { select((selected + 1) % areas.count); return }
        switch key {
        case "d": page(fraction: 0.5)
        case "u": page(fraction: -0.5)
        case " ": page(fraction: event.modifiers.contains(.shift) ? -0.9 : 0.9)
        case "g":
            if event.modifiers.contains(.shift) { jump(toEnd: true); gPending = false }
            else if gPending { jump(toEnd: false); gPending = false }
            else { gPending = true; return }
        default: break
        }
        gPending = false
    }

    private func direction(for event: KeyEvent, key: String) -> Direction? {
        if host.settings.arrowKeysScroll {
            switch event.keyCode {
            case 126: return .up
            case 125: return .down
            case 123: return .left
            case 124: return .right
            default: break
            }
        }
        switch key {
        case "k": return .up
        case "j": return .down
        case "h": return .left
        case "l": return .right
        default: return nil
        }
    }

    private func updateTicker() {
        if held.isEmpty {
            ticker?.invalidate(); ticker = nil
        } else if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            tick()
        }
    }

    private func tick() {
        let speed = host.settings.scrollPixelsPerSecond / 60 * (shiftHeld ? host.settings.dashMultiplier : 1)
        var dx = 0.0, dy = 0.0
        if held.contains(.up) { dy -= speed }
        if held.contains(.down) { dy += speed }
        if held.contains(.left) { dx -= speed }
        if held.contains(.right) { dx += speed }
        Clicker.scroll(dx: dx, dy: dy, at: areas[selected].center)
    }

    private func page(fraction: Double) {
        let total = areas[selected].frame.height * fraction
        let steps = 8
        for i in 0..<steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.016) { [weak self] in
                guard let self, !self.ended else { return }
                Clicker.scroll(dx: 0, dy: total / Double(steps), at: self.areas[self.selected].center)
            }
        }
    }

    private func jump(toEnd: Bool) {
        let area = areas[selected]
        if let bar = area.element.element("AXVerticalScrollBar"), bar.set(kAXValueAttribute, toEnd ? 1.0 : 0.0) == .success {
            return
        }
        Clicker.scroll(dx: 0, dy: toEnd ? 100_000 : -100_000, at: area.center)
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        let seconds = host.settings.scrollAutoDeactivateSeconds
        guard seconds > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in self?.host.finish() }
    }

    private func render() {
        var scene = OverlayScene()
        for (i, a) in areas.enumerated() {
            scene.outlines.append(OutlineDrawable(frame: a.frame, label: String(i + 1), selected: i == selected))
        }
        host.overlay.show(scene)
    }

    func end() {
        ended = true
        ticker?.invalidate()
        idleTimer?.invalidate()
        if let originalCursor { CGWarpMouseCursorPosition(originalCursor) }
    }

    /// Mouse location in AX coordinates (top-left origin).
    static func axMouseLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }
}
