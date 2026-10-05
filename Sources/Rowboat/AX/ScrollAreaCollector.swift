import AppKit
import ApplicationServices

/// Finds scrollable regions in the frontmost window, largest first.
enum ScrollAreaCollector {
    static let scrollRoles: Set<String> = ["AXScrollArea", "AXWebArea", "AXTable", "AXOutline", "AXList", "AXTextArea"]
    static let attributes = [kAXRoleAttribute, kAXChildrenAttribute, kAXPositionAttribute, kAXSizeAttribute]

    static func collect(app: NSRunningApplication, completion: @escaping ([ScrollArea]) -> Void) {
        ElementCollector.queue.async {
            let areas = collectSync(app: app)
            DispatchQueue.main.async { completion(areas) }
        }
    }

    static func collectSync(app: NSRunningApplication, maxNodes: Int = 6000) -> [ScrollArea] {
        let appElement = AXElement.application(pid: app.processIdentifier)
        guard let window = appElement.element(kAXFocusedWindowAttribute) ?? appElement.elements(kAXWindowsAttribute).first else { return [] }
        let screenBounds = NSScreen.screens.reduce(CGRect.null) { $0.union(ElementCollector.axRect(for: $1)) }
        let visible = (window.frame ?? screenBounds).intersection(screenBounds)
        var areas: [ScrollArea] = []
        var stack: [(AXElement, Bool)] = [(window, false)]  // (element, insideScrollArea)
        var visited = 0
        let deadline = Date().addingTimeInterval(0.7)
        while let (element, inside) = stack.popLast(), visited < maxNodes, Date() < deadline {
            visited += 1
            let v = element.values(for: attributes)
            let role = v[0] as? String ?? ""
            let frame = AXElement.frame(position: v[2], size: v[3])
            if let f = frame, !f.isEmpty, !f.intersects(visible) { continue }
            var nowInside = inside
            if scrollRoles.contains(role), let f = frame, f.width > 40, f.height > 40 {
                // Nested AXWebArea/AXTable inside an AXScrollArea is the same region; keep the outer one.
                let redundant = inside && role != "AXScrollArea"
                if !redundant {
                    areas.append(ScrollArea(element: element, frame: f.intersection(visible), role: role))
                    nowInside = true
                }
            }
            for child in (v[1] as? [AXElement] ?? []).reversed() { stack.append((child, nowInside)) }
        }
        // Drop near-duplicates (same frame reported by nested elements), keep largest first.
        var result: [ScrollArea] = []
        for area in areas.sorted(by: { $0.area > $1.area }) {
            if !result.contains(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(area.frame) && abs($0.area - area.area) < 0.15 * $0.area }) {
                result.append(area)
            }
        }
        Log.ax.info("found \(result.count) scroll areas from \(visited) nodes")
        return result
    }
}
