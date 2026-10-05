import CoreGraphics

/// Geometry helpers for hint targets. All frames use a top-left origin
/// (screen coordinates as reported by the Accessibility API).
public enum HintLayout {
    /// Indices of `frames` sorted top-to-bottom, then left-to-right, with
    /// frames whose top edges differ by at most `rowTolerance` treated as one row.
    public static func readingOrder(_ frames: [CGRect], rowTolerance: CGFloat = 6) -> [Int] {
        let byY = frames.indices.sorted { frames[$0].minY < frames[$1].minY }
        var result: [Int] = []
        var row: [Int] = []
        var rowTop: CGFloat = 0
        for i in byY {
            if row.isEmpty || frames[i].minY - rowTop > rowTolerance {
                result.append(contentsOf: row.sorted { frames[$0].minX < frames[$1].minX })
                row = [i]
                rowTop = frames[i].minY
            } else {
                row.append(i)
            }
        }
        result.append(contentsOf: row.sorted { frames[$0].minX < frames[$1].minX })
        return result
    }

    /// Indices of frames to keep after dropping near-duplicates. The first
    /// occurrence wins. Two frames are duplicates when their
    /// intersection-over-union exceeds `threshold`.
    public static func dedupe(_ frames: [CGRect], threshold: CGFloat = 0.8) -> [Int] {
        var kept: [Int] = []
        outer: for i in frames.indices {
            for k in kept where iou(frames[i], frames[k]) > threshold {
                continue outer
            }
            kept.append(i)
        }
        return kept
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, !inter.isEmpty else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }

    /// Positions labels at their anchors, nudging later labels right (then down)
    /// until they no longer overlap an earlier label.
    public static func placeLabels(anchors: [CGPoint], labelSize: CGSize, spacing: CGFloat = 2) -> [CGPoint] {
        var placed: [CGRect] = []
        var result: [CGPoint] = []
        for anchor in anchors {
            var rect = CGRect(origin: anchor, size: labelSize)
            var attempts = 0
            while placed.contains(where: { $0.intersects(rect) }) && attempts < 8 {
                attempts += 1
                if attempts <= 4 {
                    rect.origin.x += labelSize.width + spacing
                } else {
                    rect.origin.x = anchor.x
                    rect.origin.y += (labelSize.height + spacing) * CGFloat(attempts - 4)
                }
            }
            placed.append(rect)
            result.append(rect.origin)
        }
        return result
    }
}
