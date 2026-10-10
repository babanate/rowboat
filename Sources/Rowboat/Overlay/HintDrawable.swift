import AppKit

/// What the overlay draws for one target. Coordinates use AX top-left origin.
struct HintDrawable {
    enum Style { case normal, selected, dimmed }
    var label: String
    var typedCount: Int = 0           // leading characters already typed, drawn muted
    var anchor: CGPoint               // top-left of the label box
    var targetFrame: CGRect           // the element, for the selected outline
    var style: Style = .normal
}

/// A rectangle outline (scroll mode shows the selected area this way).
struct OutlineDrawable {
    var frame: CGRect
    var label: String
    var selected: Bool
}

struct OverlayScene {
    var hints: [HintDrawable] = []
    var outlines: [OutlineDrawable] = []
    var message: String? = nil        // centred badge ("No targets", search query)
    var crosshair: CGPoint? = nil     // grid mode click point
    var messageIsQuery = false
}

enum OverlayTheme {
    // Small and tight so dense screens fit more labels without crowding.
    static let font = NSFont.systemFont(ofSize: 10, weight: .bold)
    static let labelPadding = CGSize(width: 3.5, height: 1)
    static let cornerRadius: CGFloat = 3

    static var labelBackground: NSColor { NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.25, alpha: 1) }
    static var labelText: NSColor { .black }
    static var typedText: NSColor { NSColor.black.withAlphaComponent(0.35) }
    static var selectedBackground: NSColor { NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 1) }
    static var dimmedBackground: NSColor { labelBackground.withAlphaComponent(0.35) }
    static var outline: NSColor { NSColor(calibratedRed: 0.2, green: 0.6, blue: 1.0, alpha: 0.9) }
    static var badgeBackground: NSColor { NSColor.black.withAlphaComponent(0.78) }

    static func labelSize(for text: String) -> CGSize {
        let s = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(s.width) + labelPadding.width * 2, height: ceil(s.height) + labelPadding.height * 2)
    }
}
