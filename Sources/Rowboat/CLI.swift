import AppKit

/// Developer command line: inspect what the collectors see and drive a running
/// instance without pressing hotkeys.
enum CLI {
    static let activateNotification = Notification.Name("com.nathanforster.rowboat.activate")
    static let settingsNotification = Notification.Name("com.nathanforster.rowboat.settings")

    static func run(_ args: [String]) -> Int32 {
        switch args.first {
        case "--dump":
            guard let app = resolveApp(args.dropFirst().first) else { return 1 }
            var options = ElementCollector.Options()
            options.enableChromiumAccessibility = Settings.shared.enableChromiumAccessibility
            options.labelTextAndImages = Settings.shared.labelTextAndImages
            options.screenTextFallback = Settings.shared.screenTextFallback
            options.screenTextApps = Settings.shared.screenTextApps
            let t0 = Date()
            ElementCollector.refreshStatusItemsNow()
            print("status items refreshed in \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
            let (targets, report) = ElementCollector.collectSync(app: app, options: options)
            print("app: \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier) window: \(report.windowTitle)")
            print("visited \(report.visited) nodes, pruned \(report.pruned), empty frames \(report.emptyFrames), predicate \(report.predicateResults), \(targets.count) targets, \(Int(report.elapsed * 1000)) ms\(report.truncated ? " (truncated)" : "")\(report.error.map { " error: \($0)" } ?? "")")
            if report.screenText > 0 || report.screenTextError != nil {
                print("screen text: \(report.screenText) phrases in \(Int(report.screenTextElapsed * 1000)) ms\(report.screenTextError.map { " (\($0))" } ?? "")")
            }
            if RLog.echo {
                let top = report.roleCounts.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key)=\($0.value)" }
                print("roles: " + top.joined(separator: " "))
            }
            for t in targets {
                let f = t.frame
                print(String(format: "%5d %5d %5dx%-5d %-16@ %@%@", Int(f.minX), Int(f.minY), Int(f.width), Int(f.height),
                             t.role as NSString, t.displayName.prefix(60) as NSString, t.supportsPress ? "" : "  [no AXPress]"))
            }
            return 0
        case "--dump-all":
            // Every visible window, as hints mode sees them with "label every window" on.
            guard let app = resolveApp(args.dropFirst().first) else { return 1 }
            var options = ElementCollector.Options()
            options.labelTextAndImages = Settings.shared.labelTextAndImages
            options.screenTextFallback = Settings.shared.screenTextFallback
            options.screenTextApps = Settings.shared.screenTextApps
            let sem = DispatchSemaphore(value: 0)
            let t0 = Date()
            var total = 0
            ElementCollector(options: options).collectAll(app: app, batch: { b in
                total += b.targets.count
                print(String(format: "%5d ms  %-18@ %4d targets  %@", Int(b.elapsed * 1000), (b.window?.ownerName ?? app.localizedName ?? "?") as NSString, b.targets.count, (b.window?.title ?? "(focused)").prefix(40) as NSString))
            }, done: { print("done: \(total) targets in \(Int(Date().timeIntervalSince(t0) * 1000)) ms"); sem.signal() })
            // Pump the main run loop so batches delivered via DispatchQueue.main print.
            while sem.wait(timeout: .now()) != .success { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
            return 0
        case "--scroll-areas":
            guard let app = resolveApp(args.dropFirst().first) else { return 1 }
            for (i, a) in ScrollAreaCollector.collectSync(app: app).enumerated() {
                print(String(format: "%d: %-14@ %5d %5d %5dx%d", i + 1, a.role as NSString, Int(a.frame.minX), Int(a.frame.minY), Int(a.frame.width), Int(a.frame.height)))
            }
            return 0
        case "--activate":
            guard let mode = args.dropFirst().first, ModeKind(rawValue: mode) != nil else {
                print("usage: --activate hints|scroll|search"); return 2
            }
            DistributedNotificationCenter.default().postNotificationName(activateNotification, object: nil, userInfo: ["mode": mode], deliverImmediately: true)
            return 0
        case "--settings":
            DistributedNotificationCenter.default().postNotificationName(settingsNotification, object: nil, userInfo: nil, deliverImmediately: true)
            return 0
        case "--type":
            // Posts key events for each character using the current layout's
            // key codes; uppercase letters are sent with Shift. "escape",
            // "return", "tab", "space", "delete" are sent as those keys.
            guard let text = args.dropFirst().first else { print("usage: --type <characters>"); return 2 }
            for stroke in KeyPoster.strokes(for: text) { KeyPoster.tap(stroke) }
            return 0
        case "--hold":
            // --hold j 600  holds the key for 600 ms (scroll mode testing).
            guard args.count >= 3, let stroke = KeyPoster.strokes(for: args[1]).first, let ms = Int(args[2]) else {
                print("usage: --hold <key> <milliseconds>"); return 2
            }
            KeyPoster.post(stroke, down: true)
            usleep(UInt32(ms) * 1000)
            KeyPoster.post(stroke, down: false)
            return 0
        case "--trusted":
            print(Permissions.accessibilityTrusted(prompt: false))
            return 0
        default:
            print("""
            Rowboat developer CLI
              --dump [bundle-id]          list clickable targets of the frontmost (or named) app
              --dump-all [bundle-id]      every visible window, batch by batch, with timings
              --scroll-areas [bundle-id]  list scroll areas
              --activate hints|scroll|search   trigger a mode in the running app
              --settings                  open settings in the running app
              --type <chars>              post key events; uppercase adds Shift; "escape", "return", "tab", "space", "delete"
              --hold <key> <ms>           hold a key down for a while (scroll mode)
              --trusted                   print whether this process has Accessibility access
            """)
            return args.first == "--help" ? 0 : 2
        }
    }

    private static func resolveApp(_ bundleID: String?) -> NSRunningApplication? {
        if let bundleID {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
                print("no running app with bundle id \(bundleID)"); return nil
            }
            return app
        }
        return NSWorkspace.shared.frontmostApplication
    }
}

/// Posts keyboard events with real virtual key codes from the current layout.
enum KeyPoster {
    struct Stroke { var keyCode: UInt16; var flags: CGEventFlags; var text: String }

    static let named: [String: UInt16] = ["escape": 53, "return": 36, "tab": 48, "space": 49, "delete": 51,
                                           "up": 126, "down": 125, "left": 123, "right": 124]

    static var layout: [Character: UInt16] = {
        var map: [Character: UInt16] = [:]
        for code in UInt16(0)...UInt16(60) {
            if let s = KeyNames.character(for: code), let c = s.first, map[c] == nil { map[c] = code }
        }
        return map
    }()

    static func strokes(for text: String) -> [Stroke] {
        if let code = named[text.lowercased()] { return [Stroke(keyCode: code, flags: [], text: "")] }
        return text.compactMap { ch in
            let lower = Character(ch.lowercased())
            guard let code = layout[lower] else { print("no key for \(ch)"); return nil }
            return Stroke(keyCode: code, flags: ch.isUppercase ? .maskShift : [], text: String(ch))
        }
    }

    static func post(_ stroke: Stroke, down: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: stroke.keyCode, keyDown: down) else { return }
        e.flags = stroke.flags
        e.post(tap: .cghidEventTap)
    }

    static func tap(_ stroke: Stroke) {
        post(stroke, down: true); usleep(25_000)
        post(stroke, down: false); usleep(45_000)
    }
}
