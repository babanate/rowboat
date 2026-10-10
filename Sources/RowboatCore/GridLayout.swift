import CoreGraphics

/// Splits a rectangle into at most `count` cells in a grid whose shape
/// follows the rectangle's aspect ratio, row by row from the top left.
public enum GridLayout {
    public static func dimensions(for rect: CGRect, count: Int) -> (cols: Int, rows: Int) {
        guard count > 0, rect.width > 0, rect.height > 0 else { return (0, 0) }
        let aspect = rect.width / rect.height
        var cols = max(1, Int((Double(count) * Double(aspect)).squareRoot().rounded()))
        cols = min(cols, count)
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        return (cols, rows)
    }

    public static func cells(in rect: CGRect, count: Int) -> [CGRect] {
        let (cols, rows) = dimensions(for: rect, count: count)
        guard cols > 0, rows > 0 else { return [] }
        let w = rect.width / CGFloat(cols), h = rect.height / CGFloat(rows)
        var out: [CGRect] = []
        for r in 0..<rows {
            for c in 0..<cols where out.count < count {
                out.append(CGRect(x: rect.minX + CGFloat(c) * w, y: rect.minY + CGFloat(r) * h, width: w, height: h))
            }
        }
        return out
    }
}
