import CoreGraphics

/// A clickable element found by the collector. `frame` uses the Accessibility
/// API's top-left screen origin.
struct HintTarget {
    /// nil for targets found on screen rather than in the accessibility tree.
    let element: AXElement?
    let frame: CGRect
    let role: String
    let title: String
    let description: String
    let value: String
    let supportsPress: Bool

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    var searchFields: [String] { [title, description, value, role.replacingOccurrences(of: "AX", with: "")] }
    var displayName: String {
        [title, description, value].first { !$0.isEmpty } ?? role
    }
}

/// A scrollable region found by ScrollAreaCollector.
struct ScrollArea {
    let element: AXElement
    let frame: CGRect
    let role: String
    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }
    var area: CGFloat { frame.width * frame.height }
}
