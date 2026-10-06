import AppKit

/// An on-screen window from the window server, front to back, with the
/// rectangles of windows stacked above it (used to hide covered targets).
struct SceneWindow {
    let id: CGWindowID
    let pid: pid_t
    let ownerName: String
    let frame: CGRect           // AX coordinates (top-left origin)
    let coveringAbove: [CGRect]
    let isFrontmostApp: Bool
    let title: String

    /// Whether a point inside this window is actually visible.
    func isVisible(_ point: CGPoint) -> Bool {
        frame.contains(point) && !coveringAbove.contains { $0.contains(point) }
    }

    /// Fraction of the window not covered, sampled on a coarse grid.
    var visibleFraction: CGFloat {
        guard frame.width > 0, frame.height > 0 else { return 0 }
        var free = 0, total = 0
        var y = frame.minY + 10
        while y < frame.maxY {
            var x = frame.minX + 10
            while x < frame.maxX {
                total += 1
                if !coveringAbove.contains(where: { $0.contains(CGPoint(x: x, y: y)) }) { free += 1 }
                x += 40
            }
            y += 40
        }
        return total > 0 ? CGFloat(free) / CGFloat(total) : 0
    }
}

enum SceneBuilder {
    /// Visible, normal-level windows front to back, excluding our own and
    /// anything smaller than a palette. `frontmostPid` marks the active app.
    static func windows(frontmostPid: pid_t, minVisibleFraction: CGFloat = 0.04) -> [SceneWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPid = ProcessInfo.processInfo.processIdentifier
        var covering: [CGRect] = []
        var result: [SceneWindow] = []
        for info in list {
            guard let layer = info["kCGWindowLayer"] as? Int, layer == 0,
                  let pid = info["kCGWindowOwnerPID"] as? pid_t, pid != ownPid,
                  let b = info["kCGWindowBounds"] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let w = b["Width"], let h = b["Height"],
                  w >= 120, h >= 60,
                  (info["kCGWindowAlpha"] as? CGFloat ?? 1) > 0.05 else { continue }
            let frame = CGRect(x: x, y: y, width: w, height: h)
            let window = SceneWindow(id: info["kCGWindowNumber"] as? CGWindowID ?? 0, pid: pid,
                                     ownerName: info["kCGWindowOwnerName"] as? String ?? "",
                                     frame: frame, coveringAbove: covering, isFrontmostApp: pid == frontmostPid,
                                     title: info["kCGWindowName"] as? String ?? "")
            if window.visibleFraction >= minVisibleFraction { result.append(window) }
            covering.append(frame)
        }
        return result
    }
}
