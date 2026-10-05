import AppKit

/// A transparent, click-through panel covering one screen.
final class OverlayWindow: NSPanel {
    let overlayView = OverlayView()
    let screenAXFrame: CGRect

    init(screen: NSScreen) {
        screenAXFrame = ElementCollector.axRect(for: screen)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .screenSaver
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
        overlayView.frame = contentView!.bounds
        overlayView.autoresizingMask = [.width, .height]
        contentView?.addSubview(overlayView)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    /// Never let AppKit shrink or move the overlay; it must cover the screen exactly.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func coverScreen() {
        guard let screen = NSScreen.screens.first(where: { ElementCollector.axRect(for: $0) == screenAXFrame }) else { return }
        if frame != screen.frame { setFrame(screen.frame, display: false) }
    }

    /// Converts an AX (top-left origin) rect to this view's coordinates (bottom-left origin).
    func localRect(_ ax: CGRect) -> CGRect {
        CGRect(x: ax.minX - screenAXFrame.minX,
               y: screenAXFrame.maxY - ax.maxY,
               width: ax.width, height: ax.height)
    }

    func render(_ scene: OverlayScene) {
        var local = scene
        local.hints = scene.hints.compactMap { h in
            let size = OverlayTheme.labelSize(for: h.label)
            let axBox = CGRect(origin: h.anchor, size: size)
            guard axBox.intersects(screenAXFrame) else { return nil }
            var c = h
            c.anchor = localRect(axBox).origin
            c.targetFrame = localRect(h.targetFrame)
            return c
        }
        local.outlines = scene.outlines.compactMap { o in
            guard o.frame.intersects(screenAXFrame) else { return nil }
            var c = o
            c.frame = localRect(o.frame)
            return c
        }
        overlayView.scene = local
        overlayView.needsDisplay = true
    }
}

/// Draws labels, outlines and a badge with CoreGraphics. A few hundred labels
/// draw in well under a frame.
final class OverlayView: NSView {
    var scene = OverlayScene()

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        for o in scene.outlines {
            let path = NSBezierPath(roundedRect: o.frame.insetBy(dx: 1.5, dy: 1.5), xRadius: 6, yRadius: 6)
            path.lineWidth = o.selected ? 3 : 1.5
            (o.selected ? OverlayTheme.outline : OverlayTheme.outline.withAlphaComponent(0.4)).setStroke()
            path.stroke()
            if o.selected {
                OverlayTheme.outline.withAlphaComponent(0.06).setFill()
                path.fill()
            }
            drawLabel(o.label, typedCount: 0, at: CGPoint(x: o.frame.minX + 6, y: o.frame.maxY - OverlayTheme.labelSize(for: o.label).height - 6),
                      style: o.selected ? .selected : .normal, ctx: ctx)
        }

        for h in scene.hints where h.style == .selected {
            let path = NSBezierPath(roundedRect: h.targetFrame.insetBy(dx: -1, dy: -1), xRadius: 3, yRadius: 3)
            path.lineWidth = 2
            OverlayTheme.outline.setStroke()
            path.stroke()
        }
        for h in scene.hints {
            drawLabel(h.label, typedCount: h.typedCount, at: h.anchor, style: h.style, ctx: ctx)
        }

        if let message = scene.message {
            drawBadge(message, isQuery: scene.messageIsQuery)
        }
    }

    private func drawLabel(_ text: String, typedCount: Int, at origin: CGPoint, style: HintDrawable.Style, ctx: CGContext) {
        let size = OverlayTheme.labelSize(for: text)
        let box = CGRect(origin: origin, size: size)
        let background: NSColor
        switch style {
        case .normal: background = OverlayTheme.labelBackground
        case .selected: background = OverlayTheme.selectedBackground
        case .dimmed: background = OverlayTheme.dimmedBackground
        }
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        background.setFill()
        NSBezierPath(roundedRect: box, xRadius: OverlayTheme.cornerRadius, yRadius: OverlayTheme.cornerRadius).fill()
        ctx.restoreGState()

        let attributed = NSMutableAttributedString(string: text.uppercased(), attributes: [
            .font: OverlayTheme.font, .foregroundColor: style == .selected ? NSColor.white : OverlayTheme.labelText,
        ])
        if typedCount > 0, typedCount <= text.count {
            attributed.addAttribute(.foregroundColor, value: OverlayTheme.typedText, range: NSRange(location: 0, length: typedCount))
        }
        attributed.draw(at: CGPoint(x: box.minX + OverlayTheme.labelPadding.width, y: box.minY + OverlayTheme.labelPadding.height))
    }

    private func drawBadge(_ text: String, isQuery: Bool) {
        let font = NSFont.systemFont(ofSize: 18, weight: .medium)
        let display = isQuery ? (text.isEmpty ? "Type to search…" : text) : text
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: text.isEmpty && isQuery ? NSColor.white.withAlphaComponent(0.5) : NSColor.white]
        let size = (display as NSString).size(withAttributes: attrs)
        let width = max(size.width + 36, isQuery ? 360 : 0)
        let box = CGRect(x: (bounds.width - width) / 2, y: isQuery ? 80 : bounds.midY - 20, width: width, height: size.height + 20)
        OverlayTheme.badgeBackground.setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        (display as NSString).draw(at: CGPoint(x: box.minX + 18, y: box.minY + 10), withAttributes: attrs)
        if isQuery {
            // caret
            NSColor.white.setFill()
            NSBezierPath(rect: CGRect(x: box.minX + 18 + (text.isEmpty ? 0 : size.width) + 2, y: box.minY + 10, width: 2, height: size.height)).fill()
        }
    }
}
