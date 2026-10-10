import AppKit
import RowboatCore

/// Click anywhere without accessibility: each letter zooms into a cell of a
/// grid over the screen under the mouse; Return or Space clicks the centre
/// of the current region (Shift right-clicks, ⌘ command-clicks, ⌥
/// double-clicks); arrows nudge; Delete zooms back out; Escape leaves.
final class GridMode: Mode {
    let kind: ModeKind = .grid
    private unowned let host: ModeHost
    private var stack: [CGRect] = []        // zoom history, last is current region
    private var point: CGPoint = .zero      // click point, AX coordinates
    private var alphabet: [Character] = []
    private var ended = false

    init(host: ModeHost) { self.host = host }

    private var region: CGRect { stack.last ?? .zero }
    private var cells: [CGRect] { GridLayout.cells(in: region, count: alphabet.count) }

    func begin() {
        alphabet = LabelGenerator(alphabet: host.settings.labelCharacters).alphabet
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        stack = [ElementCollector.axRect(for: screen)]
        point = CGPoint(x: region.midX, y: region.midY)
        render()
    }

    func handle(_ event: KeyEvent) {
        guard event.kind == .down else { return }
        if event.isEscape { host.finish(); return }
        if event.isReturn || event.isSpace { click(event.clickKind); return }
        if event.isBackspace {
            if stack.count > 1 { stack.removeLast(); point = CGPoint(x: region.midX, y: region.midY); render() }
            return
        }
        let step: CGFloat = event.modifiers.contains(.shift) ? 20 : 4
        switch event.keyCode {
        case 123: nudge(-step, 0); return
        case 124: nudge(step, 0); return
        case 125: nudge(0, step); return
        case 126: nudge(0, -step); return
        default: break
        }
        let ch = Character(event.charactersIgnoringModifiers.lowercased())
        guard let index = alphabet.firstIndex(of: ch), index < cells.count else { return }
        let cell = cells[index]
        point = CGPoint(x: cell.midX, y: cell.midY)
        // Stop zooming once cells would be smaller than a few points.
        if cell.width >= 24 && cell.height >= 16 { stack.append(cell) }
        render()
    }

    private func nudge(_ dx: CGFloat, _ dy: CGFloat) {
        point.x += dx; point.y += dy
        render()
    }

    private func click(_ kind: ClickKind) {
        ended = true
        let target = point
        host.finish()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            Clicker.synthesizeClick(at: target, kind: kind)
        }
    }

    private func render() {
        var scene = OverlayScene()
        for (i, cell) in cells.enumerated() {
            scene.outlines.append(OutlineDrawable(frame: cell, label: String(alphabet[i]), selected: false))
        }
        if stack.count > 1 {
            scene.outlines.append(OutlineDrawable(frame: region, label: "", selected: true))
        }
        scene.crosshair = point
        host.overlay.show(scene)
        CGWarpMouseCursorPosition(point)
    }

    func end() { ended = true }
}
