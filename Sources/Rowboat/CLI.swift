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
            let (targets, report) = ElementCollector.collectSync(app: app, options: options)
            print("app: \(app.bundleIdentifier ?? "?") pid \(app.processIdentifier) window: \(report.windowTitle)")
            print("visited \(report.visited) nodes, pruned \(report.pruned), \(targets.count) targets, \(Int(report.elapsed * 1000)) ms\(report.truncated ? " (truncated)" : "")\(report.error.map { " error: \($0)" } ?? "")")
            for t in targets {
                let f = t.frame
                print(String(format: "%5d %5d %5dx%-5d %-16@ %@%@", Int(f.minX), Int(f.minY), Int(f.width), Int(f.height),
                             t.role as NSString, t.displayName.prefix(60) as NSString, t.supportsPress ? "" : "  [no AXPress]"))
            }
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
            // Posts key events for each character, for driving modes in tests.
            guard let text = args.dropFirst().first else { print("usage: --type <characters>"); return 2 }
            for ch in (text == "escape" ? "\u{1B}" : text) {
                let code: UInt16 = ch == "\u{1B}" ? 53 : (ch == "\n" ? 36 : 0)
                for down in [true, false] {
                    guard let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) else { continue }
                    if code == 0 {
                        var units = Array(String(ch).utf16)
                        e.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
                    }
                    e.post(tap: .cghidEventTap)
                    usleep(30_000)
                }
            }
            return 0
        case "--trusted":
            print(Permissions.accessibilityTrusted(prompt: false))
            return 0
        default:
            print("""
            Rowboat developer CLI
              --dump [bundle-id]          list clickable targets of the frontmost (or named) app
              --scroll-areas [bundle-id]  list scroll areas
              --activate hints|scroll|search   trigger a mode in the running app
              --settings                  open settings in the running app
              --type <chars>              post key events (--type escape sends Escape)
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
