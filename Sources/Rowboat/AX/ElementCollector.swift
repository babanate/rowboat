import AppKit
import ApplicationServices
import RowboatCore

/// Collects clickable elements from the frontmost window of an application.
/// All AX traffic runs on `queue`; callbacks arrive on the main thread.
final class ElementCollector {
    static let queue = DispatchQueue(label: "rowboat.ax", qos: .userInteractive)

    struct Options {
        var maxNodes = 15_000
        var maxDepth = 80
        var timeBudget: TimeInterval = 0.9
        var enableChromiumAccessibility = true
        var messagingTimeout: Float = 0.5
    }

    struct Report {
        var visited = 0
        var pruned = 0
        var candidates = 0
        var elapsed: TimeInterval = 0
        var truncated = false
        var windowTitle = ""
        var error: String?
    }

    /// Roles that are targets even without an AXPress action.
    static let clickableRoles: Set<String> = [
        "AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXMenuItem", "AXMenuBarItem", "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
        "AXSlider", "AXIncrementor", "AXDisclosureTriangle", "AXTab", "AXTabGroup", "AXCell", "AXRow",
        "AXColorWell", "AXSwitch", "AXToggle", "AXDockItem", "AXHandle", "AXValueIndicator",
    ]
    /// Roles never shown as targets, even with AXPress.
    static let structuralRoles: Set<String> = [
        "AXWindow", "AXSheet", "AXDrawer", "AXScrollArea", "AXSplitGroup", "AXSplitter", "AXToolbar",
        "AXWebArea", "AXLayoutArea", "AXTabGroup", "AXMenuBar", "AXMenu",
    ]
    /// Roles that are not separate targets when an ancestor is already one
    /// (the text inside a link, the cells of a row, the icon in a button).
    static let passiveInsideTarget: Set<String> = [
        "AXStaticText", "AXImage", "AXGroup", "AXHeading", "AXCell", "AXUnknown", "AXGenericElement", "AXText", "AXList",
    ]
    static let attributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXChildrenAttribute, "AXVisibleChildren",
        kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        kAXValueAttribute, kAXEnabledAttribute,
    ]

    private let options: Options
    init(options: Options = Options()) { self.options = options }

    func collect(app: NSRunningApplication, completion: @escaping ([HintTarget], Report) -> Void) {
        let options = self.options
        Self.queue.async {
            let (targets, report) = Self.collectSync(app: app, options: options)
            DispatchQueue.main.async { completion(targets, report) }
        }
    }

    static func collectSync(app: NSRunningApplication, options: Options) -> ([HintTarget], Report) {
        let start = Date()
        var report = Report()
        AXUIElementSetMessagingTimeout(AXElement.systemWide.raw, options.messagingTimeout)
        let appElement = AXElement.application(pid: app.processIdentifier)

        if options.enableChromiumAccessibility, Settings.shared.isChromium(bundleIdentifier: app.bundleIdentifier) || ElectronDetector.isElectron(app) {
            appElement.set("AXEnhancedUserInterface", true)
            appElement.set("AXManualAccessibility", true)
        }

        guard let window = appElement.element(kAXFocusedWindowAttribute) ?? appElement.elements(kAXWindowsAttribute).first else {
            report.error = "no window"
            report.elapsed = Date().timeIntervalSince(start)
            return ([], report)
        }
        report.windowTitle = window.string(kAXTitleAttribute) ?? ""
        let screenBounds = NSScreen.screens.reduce(CGRect.null) { $0.union(Self.axRect(for: $1)) }
        let windowFrame = window.frame ?? screenBounds
        let visible = windowFrame.intersection(screenBounds)

        var found: [HintTarget] = []
        // (element, depth, inside an element that is already a target)
        var stack: [(AXElement, Int, Bool)] = [(window, 0, false)]
        // Also include open menus and popovers of the app (combo box lists, context menus).
        for extra in appElement.children where extra != window {
            if let role = extra.role, role == "AXMenu" || role == "AXPopover" || role == "AXSheet" {
                stack.append((extra, 0, false))
            }
        }
        let deadline = start.addingTimeInterval(options.timeBudget)

        while let (element, depth, insideTarget) = stack.popLast() {
            if report.visited >= options.maxNodes || Date() > deadline {
                report.truncated = true
                break
            }
            report.visited += 1
            let v = element.values(for: attributes)
            let role = v[0] as? String ?? ""
            let frame = AXElement.frame(position: v[4], size: v[5])

            // Prune subtrees that are entirely outside the visible region.
            if let f = frame, !f.isEmpty, !f.intersects(visible) {
                report.pruned += 1
                continue
            }
            if depth >= options.maxDepth { continue }

            let isStructural = structuralRoles.contains(role)
            var isTarget = false
            if !isStructural, !(insideTarget && passiveInsideTarget.contains(role)),
               let f = frame, f.width >= 2, f.height >= 2, f.intersects(visible) {
                let enabled = (v[9] as? Bool) ?? true
                let actions = element.actionNames
                let press = actions.contains(kAXPressAction)
                let clickable = press || clickableRoles.contains(role) || actions.contains("AXOpen") || actions.contains("AXConfirm")
                if clickable && enabled {
                    isTarget = true
                    report.candidates += 1
                    found.append(HintTarget(
                        element: element, frame: f.intersection(visible), role: role,
                        title: Self.text(v[6]), description: Self.text(v[7]), value: Self.text(v[8]),
                        supportsPress: press))
                }
            }

            let visibleChildren = v[3] as? [AXElement] ?? []
            let children = visibleChildren.isEmpty ? (v[2] as? [AXElement] ?? []) : visibleChildren
            // Push in reverse so traversal order stays document order.
            for child in children.reversed() { stack.append((child, depth + 1, insideTarget || isTarget)) }
        }

        let keep = HintLayout.dedupe(found.map(\.frame))
        var targets = keep.map { found[$0] }
        let order = HintLayout.readingOrder(targets.map(\.frame))
        targets = order.map { targets[$0] }
        report.elapsed = Date().timeIntervalSince(start)
        Log.ax.info("collected \(targets.count) targets from \(report.visited) nodes in \(Int(report.elapsed * 1000)) ms (pruned \(report.pruned), truncated \(report.truncated))")
        return (targets, report)
    }

    static func text(_ value: Any?) -> String {
        switch value {
        case let s as String: return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        case let b as Bool: return b ? "on" : "off"
        default: return ""
        }
    }

    /// An NSScreen's frame in Accessibility coordinates (top-left origin of the primary screen).
    static func axRect(for screen: NSScreen) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let f = screen.frame
        return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
    }
}

/// Detects Electron apps by their bundled framework, cached per bundle.
enum ElectronDetector {
    private static var cache: [String: Bool] = [:]
    private static let lock = NSLock()

    static func isElectron(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        lock.lock(); defer { lock.unlock() }
        if let cached = cache[url.path] { return cached }
        let frameworks = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path
        let result = FileManager.default.fileExists(atPath: frameworks)
        cache[url.path] = result
        return result
    }
}
