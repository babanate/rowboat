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
        /// Use AXUIElementsForSearchPredicate on web areas (Chromium, WebKit).
        /// Visible elements of a long page come back in ~10 ms instead of a
        /// walk that can take a second. Falls back to the walk when unsupported.
        var useSearchPredicate = true
        /// Static text and images in native views become targets (Homerow does this).
        var labelTextAndImages = true
    }

    struct Report {
        var visited = 0
        var pruned = 0
        var candidates = 0
        var elapsed: TimeInterval = 0
        var truncated = false
        var windowTitle = ""
        var visibleFrame = CGRect.zero
        var emptyFrames = 0
        var predicateResults = 0
        var wantsEnhancedInterface = false
        var enabledEnhancedInterface = false
        var retried = false
        var roleCounts: [String: Int] = [:]
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
    static let subroleNames = [
        "AXCloseButton": "Close", "AXMinimizeButton": "Minimize", "AXZoomButton": "Zoom",
        "AXFullScreenButton": "Full Screen", "AXToolbarButton": "Toolbar", "AXSearchField": "Search",
        "AXIncrementArrow": "Increment", "AXDecrementArrow": "Decrement", "AXSortButton": "Sort",
    ]
    static let attributes = [
        kAXRoleAttribute, kAXSubroleAttribute, kAXChildrenAttribute, "AXVisibleChildren",
        kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXDescriptionAttribute,
        kAXValueAttribute, kAXEnabledAttribute, "AXContents", "AXVisibleRows",
    ]

    private let options: Options
    init(options: Options = Options()) { self.options = options }

    func collect(app: NSRunningApplication, completion: @escaping ([HintTarget], Report) -> Void) {
        let options = self.options
        Self.queue.async {
            let (targets, report) = Self.collectSync(app: app, options: options)
            DispatchQueue.main.async { completion(targets, report) }
            Self.refreshStatusItemsIfStale()
        }
    }

    // MARK: status items cache

    private static var cachedStatusItems: [HintTarget] = []
    private static var statusItemsRefreshedAt = Date.distantPast

    /// Re-reads the status items on the AX queue when the cache is older than
    /// `maxAge` seconds. Safe to call from any thread.
    static func refreshStatusItemsIfStale(maxAge: TimeInterval = 15) {
        queue.async {
            guard Date().timeIntervalSince(statusItemsRefreshedAt) > maxAge else { return }
            let bounds = NSScreen.screens.reduce(CGRect.null) { $0.union(axRect(for: $1)) }
            AXUIElementSetMessagingTimeout(AXElement.systemWide.raw, 0.05)
            let items = statusItems(excluding: ProcessInfo.processInfo.processIdentifier, within: bounds)
            AXUIElementSetMessagingTimeout(AXElement.systemWide.raw, 0.5)
            cachedStatusItems = items
            statusItemsRefreshedAt = Date()
            Log.ax.info("status items cached: \(items.count)")
        }
    }

    /// Blocking refresh for the command line.
    static func refreshStatusItemsNow() {
        statusItemsRefreshedAt = .distantPast
        refreshStatusItemsIfStale()
        queue.sync {}
    }

    static func collectSync(app: NSRunningApplication, options: Options) -> ([HintTarget], Report) {
        var (targets, report) = walkOnce(app: app, options: options)
        // Chromium, Electron and WebKit build their trees asynchronously after the
        // first request (Electron even reports the enhanced interface as already
        // on); a near-empty result from such an app means it was not ready yet.
        if report.wantsEnhancedInterface, targets.count < 5 {
            usleep(1_000_000)
            (targets, report) = walkOnce(app: app, options: options)
            report.retried = true
        }
        return (targets, report)
    }

    private static func walkOnce(app: NSRunningApplication, options: Options) -> ([HintTarget], Report) {
        let start = Date()
        var report = Report()
        AXUIElementSetMessagingTimeout(AXElement.systemWide.raw, options.messagingTimeout)
        let appElement = AXElement.application(pid: app.processIdentifier)

        // Safari shows its web area, and Chromium/Electron their whole page, only
        // once an assistive client asks for the enhanced interface. Safari reports
        // "not implemented" for the set and honours it anyway.
        let settings = Settings.shared
        let wantsEnhanced = settings.isWebKitBrowser(bundleIdentifier: app.bundleIdentifier)
            || (options.enableChromiumAccessibility && (settings.isChromium(bundleIdentifier: app.bundleIdentifier) || ElectronDetector.isElectron(app)))
        report.wantsEnhancedInterface = wantsEnhanced
        if wantsEnhanced {
            let already = (appElement.value("AXEnhancedUserInterface") as? Bool) ?? false
            appElement.set("AXEnhancedUserInterface", true)
            appElement.set("AXManualAccessibility", true)
            if !already {
                report.enabledEnhancedInterface = true
                usleep(250_000)  // first time: give the app a moment to build its tree
            }
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
        // Menu bars sit above the window; let targets anywhere on screen through
        // but keep window geometry for label placement.
        let reach = visible.union(CGRect(x: screenBounds.minX, y: screenBounds.minY, width: screenBounds.width, height: 40))
        report.visibleFrame = visible

        var found: [HintTarget] = []
        // (element, depth, inside an element that is already a target)
        var stack: [(AXElement, Int, Bool)] = [(window, 0, false)]
        // Also include open menus and popovers of the app (combo box lists, context menus).
        for extra in appElement.children where extra != window {
            if let role = extra.role, role == "AXMenu" || role == "AXPopover" || role == "AXSheet" {
                stack.append((extra, 0, false))
            }
        }
        // The app's menu bar (File, Edit, ...) and the status items on the right,
        // walked after the window (the stack pops from the end).
        if let extras = appElement.element("AXExtrasMenuBar") { stack.insert((extras, 0, false), at: 0) }
        if let menuBar = appElement.element(kAXMenuBarAttribute) { stack.insert((menuBar, 0, false), at: 0) }
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
            if RLog.echo { report.roleCounts[role, default: 0] += 1 }
            if frame?.isEmpty ?? true { report.emptyFrames += 1 }

            // Prune subtrees that are entirely outside the visible region.
            if let f = frame, !f.isEmpty, !f.intersects(reach) {
                report.pruned += 1
                continue
            }
            if depth >= options.maxDepth { continue }

            if role == "AXWebArea", options.useSearchPredicate,
               let results = Self.searchPredicate(on: element) {
                report.predicateResults += results.count
                for r in results {
                    guard let target = Self.target(from: r, visible: visible) else { continue }
                    report.candidates += 1
                    found.append(target)
                }
                continue  // the predicate covered this subtree
            }

            let isStructural = structuralRoles.contains(role)
            var isTarget = false
            if !isStructural, !(insideTarget && passiveInsideTarget.contains(role)),
               let f = frame, f.width >= 2, f.height >= 2, f.intersects(reach) {
                let enabled = (v[9] as? Bool) ?? true
                let actions = element.actionNames
                let press = actions.contains(kAXPressAction)
                let textOrImage = options.labelTextAndImages && !insideTarget && (role == "AXStaticText" || role == "AXImage")
                let clickable = press || clickableRoles.contains(role) || actions.contains("AXOpen") || actions.contains("AXConfirm") || textOrImage
                if clickable && enabled {
                    isTarget = true
                    report.candidates += 1
                    var title = Self.text(v[6])
                    let description = Self.text(v[7])
                    let value = Self.text(v[8])
                    if title.isEmpty, description.isEmpty, value.isEmpty {
                        if role == "AXRow" || role == "AXCell" {
                            title = Self.innerText(of: v[2] as? [AXElement] ?? [])
                        } else if let subrole = v[1] as? String, let name = subroleNames[subrole] {
                            title = name
                        }
                    }
                    found.append(HintTarget(
                        element: element, frame: f.intersection(reach), role: role,
                        title: title, description: description, value: value,
                        supportsPress: press))
                }
            }

            // A closed menu's items have no frames and can number in the thousands
            // (Chrome's bookmarks); open menus arrive as AXMenu children of the app.
            if role == "AXMenuBarItem" || role == "AXMenuButton" { continue }
            // Tables and outlines with thousands of rows: only the visible rows matter.
            let visibleRows = v[11] as? [AXElement] ?? []
            let visibleChildren = v[3] as? [AXElement] ?? []
            var children = !visibleRows.isEmpty ? visibleRows : (visibleChildren.isEmpty ? (v[2] as? [AXElement] ?? []) : visibleChildren)
            // Finder's column view exposes its items only through AXContents.
            if children.isEmpty, let contents = v[10] as? [AXElement] { children = contents }
            // Push in reverse so traversal order stays document order.
            for child in children.reversed() { stack.append((child, depth + 1, insideTarget || isTarget)) }
        }

        // Status items on the right of the menu bar belong to other apps, each
        // exposing its own AXExtrasMenuBar. Asking every app takes over a second
        // on a busy Mac, so activation reads a cache that is refreshed afterwards.
        found.append(contentsOf: cachedStatusItems.filter { $0.frame.intersects(screenBounds) })

        let keep = HintLayout.dedupe(found.map(\.frame))
        var targets = keep.map { found[$0] }
        let order = HintLayout.readingOrder(targets.map(\.frame))
        targets = order.map { targets[$0] }
        report.elapsed = Date().timeIntervalSince(start)
        Log.ax.info("collected \(targets.count) targets from \(report.visited) nodes in \(Int(report.elapsed * 1000)) ms (pruned \(report.pruned), truncated \(report.truncated))")
        return (targets, report)
    }

    static func statusItems(excluding pid: pid_t, within bounds: CGRect) -> [HintTarget] {
        var targets: [HintTarget] = []
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.processIdentifier != pid && !$0.isTerminated && ($0.activationPolicy == .accessory || $0.activationPolicy == .regular)
        }
        for app in apps {
            let element = AXElement.application(pid: app.processIdentifier)
            AXUIElementSetMessagingTimeout(element.raw, 0.05)
            guard let bar = element.element("AXExtrasMenuBar") else { continue }
            for item in bar.children {
                let v = item.values(for: [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXDescriptionAttribute])
                // Items hidden by a menu bar manager report frames elsewhere on screen; keep the menu bar band only.
                guard let f = AXElement.frame(position: v[1], size: v[2]), f.width >= 2, f.height >= 2, f.intersects(bounds),
                      f.minY >= bounds.minY, f.maxY <= bounds.minY + 40 else { continue }
                targets.append(HintTarget(element: item, frame: f, role: v[0] as? String ?? "AXMenuBarItem",
                                          title: text(v[3]), description: text(v[4]).isEmpty ? (app.localizedName ?? "") : text(v[4]),
                                          value: "", supportsPress: true))
            }
        }
        return targets
    }

    static let predicateKeys = [
        "AXButtonSearchKey", "AXCheckBoxSearchKey", "AXControlSearchKey", "AXLinkSearchKey",
        "AXTextFieldSearchKey", "AXRadioGroupSearchKey", "AXKeyboardFocusableSearchKey",
        "AXGraphicSearchKey",
    ]

    /// Visible interactive elements of a web area via the (private but long
    /// standing) search predicate parameterized attribute. nil when unsupported.
    static func searchPredicate(on webArea: AXElement) -> [AXElement]? {
        let predicate: [String: Any] = [
            "AXDirection": "AXDirectionNext", "AXImmediateDescendantsOnly": false,
            "AXResultsLimit": 2000, "AXVisibleOnly": true, "AXSearchKey": predicateKeys,
        ]
        guard let results = webArea.parameterized("AXUIElementsForSearchPredicate", parameter: predicate) as? [AXElement] else {
            return nil
        }
        // Clickable cards and rows are plain groups with a click handler; the
        // standard keys skip them. Pull every visible element once and keep the
        // groups that are pressable and carry a name (nameless ones are layout).
        let anyPredicate: [String: Any] = [
            "AXDirection": "AXDirectionNext", "AXImmediateDescendantsOnly": false,
            "AXResultsLimit": 3000, "AXVisibleOnly": true, "AXSearchKey": ["AXAnyTypeSearchKey"],
        ]
        guard let everything = webArea.parameterized("AXUIElementsForSearchPredicate", parameter: anyPredicate) as? [AXElement] else {
            return results
        }
        let known = Set(results)
        var extra: [AXElement] = []
        for element in everything where !known.contains(element) {
            let v = element.values(for: [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute])
            guard let role = v[0] as? String, role == "AXGroup" || role == "AXStaticText" || role == "AXCell" || role == "AXRow" || role == "AXListItem" else { continue }
            let named = !text(v[1]).isEmpty || !text(v[2]).isEmpty
            guard named, element.actionNames.contains(kAXPressAction) else { continue }
            extra.append(element)
        }
        return results + extra
    }

    /// Builds a target from an element returned by the predicate.
    static func target(from element: AXElement, visible: CGRect) -> HintTarget? {
        let v = element.values(for: [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXEnabledAttribute])
        let role = v[0] as? String ?? ""
        guard !structuralRoles.contains(role), (v[6] as? Bool) ?? true,
              let f = AXElement.frame(position: v[1], size: v[2]), f.width >= 2, f.height >= 2, f.intersects(visible) else { return nil }
        let actions = element.actionNames
        return HintTarget(element: element, frame: f.intersection(visible), role: role,
                          title: text(v[3]), description: text(v[4]), value: text(v[5]),
                          supportsPress: actions.contains(kAXPressAction))
    }

    /// First static text found up to two levels below `children` (rows hold
    /// cells, cells hold text). Bounded to a handful of IPC calls.
    static func innerText(of children: [AXElement]) -> String {
        var queue = children.prefix(4).map { ($0, 0) }
        var looked = 0
        while !queue.isEmpty, looked < 8 {
            let (el, depth) = queue.removeFirst()
            looked += 1
            let v = el.values(for: [kAXRoleAttribute, kAXValueAttribute, kAXTitleAttribute, kAXChildrenAttribute])
            let role = v[0] as? String ?? ""
            if role == "AXStaticText" || role == "AXTextField" {
                let t = text(v[1]).isEmpty ? text(v[2]) : text(v[1])
                if !t.isEmpty { return t }
            }
            if depth < 1 { queue.append(contentsOf: (v[3] as? [AXElement] ?? []).prefix(4).map { ($0, depth + 1) }) }
        }
        return ""
    }

    static func text(_ value: Any?) -> String {
        switch value {
        case let s as String:
            // Multi-line titles (Chrome extension buttons) keep only their first line.
            return s.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
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
