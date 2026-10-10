import AppKit
import RowboatCore

/// Labels every clickable element; typing a label clicks it. With
/// `searchable`, typed text filters targets instead and digits pick a match.
final class HintsMode: Mode {
    let kind: ModeKind
    private unowned let host: ModeHost
    private let searchable: Bool
    private var targets: [HintTarget] = []
    private var labels: [String] = []
    private var anchors: [CGPoint] = []
    private var allocator: LabelAllocator?
    private let began = Date()
    private var labelSize = CGSize(width: 20, height: 14)
    private var typed = ""
    private var query = ""
    private var matches: [Int] = []
    private var loaded = false
    private var ended = false
    private var pending: [KeyEvent] = []
    private static let searchLabels = (1...9).map(String.init)

    init(host: ModeHost, searchable: Bool) {
        self.host = host
        self.searchable = searchable
        self.kind = searchable ? .search : .hints
    }

    func begin() {
        var options = ElementCollector.Options()
        options.enableChromiumAccessibility = host.settings.enableChromiumAccessibility
        options.labelTextAndImages = host.settings.labelTextAndImages
        options.screenTextFallback = host.settings.screenTextFallback
        options.screenTextApps = host.settings.screenTextApps
        if searchable { render() }
        let collector = ElementCollector(options: options)
        if host.settings.labelAllWindows {
            collector.collectAll(app: host.app, batch: { [weak self] batch in
                guard let self else { return }
                if batch.screenTextError == "no screen recording permission" {
                    Self.askForScreenRecordingOnce()
                    if self.targets.count < 12 { self.host.overlay.flash("Rowboat needs Screen Recording for this app", duration: 1.6) }
                }
                self.absorb(batch.targets, visible: batch.window?.frame, windowsPending: batch.windowsPending)
            }, done: { [weak self] in
                guard let self, !self.ended, self.targets.isEmpty else { return }
                self.host.overlay.flash("No targets")
                self.host.finish()
            })
        } else {
            collector.collect(app: host.app) { [weak self] targets, report in
                guard let self, !self.ended else { return }
                if report.screenTextError == "no screen recording permission" { Self.askForScreenRecordingOnce() }
                if targets.isEmpty {
                    self.host.overlay.flash(report.error == nil ? "No targets" : "No window")
                    self.host.finish()
                    return
                }
                self.absorb(targets, visible: report.visibleFrame)
            }
        }
    }

    /// Adds a batch of targets. The first batch sizes the label pool; later
    /// ones get fresh labels without touching the ones already on screen.
    private func absorb(_ batch: [HintTarget], visible: CGRect?, windowsPending: Int = 0) {
        guard !ended, !batch.isEmpty else { return }
        let screen = NSScreen.screens.reduce(CGRect.null) { $0.union(ElementCollector.axRect(for: $1)) }
        let region = visible ?? screen
        if allocator == nil {
            allocator = LabelAllocator(alphabet: host.settings.labelCharacters)
            labelSize = OverlayTheme.labelSize(for: "WW")
        }
        let first = targets.isEmpty
        targets.append(contentsOf: batch)
        if !searchable { labels.append(contentsOf: allocator!.next(batch.count)) }
        // Existing anchors are placed first in the same order, so they keep their spots.
        let raw = anchors + batch.map { HintLayout.labelAnchor(for: $0.frame, labelSize: labelSize, within: region.isNull ? screen : region) }
        anchors = HintLayout.placeLabels(anchors: raw, labelSize: labelSize)
        if RLog.echo, !searchable {
            for (i, t) in batch.enumerated() {
                let idx = targets.count - batch.count + i
                Log.mode.info("label \(labels[idx]) -> \(t.role) '\(t.displayName)' @\(Int(t.frame.minX)),\(Int(t.frame.minY))")
            }
        }
        if searchable { updateMatches() }
        let t = Date()
        render()
        Log.mode.info("\(first ? "first paint" : "batch") \(batch.count) targets at +\(Int(Date().timeIntervalSince(began) * 1000)) ms (render \(Int(Date().timeIntervalSince(t) * 1000)) ms, total \(targets.count))")
        if first {
            loaded = true
            let replay = pending
            pending = []
            replay.forEach(handle)
        }
    }

    private static var askedForScreenRecording = false
    /// The first time screen text is needed without permission, open the
    /// system prompt once; later activations stay quiet.
    static func askForScreenRecordingOnce() {
        guard !askedForScreenRecording else { return }
        askedForScreenRecording = true
        Log.ax.warning("screen recording permission missing; asking")
        _ = ScreenCapture.hasPermission(prompt: true)
    }

    func handle(_ event: KeyEvent) {
        guard event.kind == .down else { return }
        if event.isEscape { host.finish(); return }
        if !loaded { pending.append(event); return }
        if searchable { handleSearch(event) } else { handleLabel(event) }
    }

    private func handleLabel(_ event: KeyEvent) {
        if event.isBackspace {
            if !typed.isEmpty { typed.removeLast(); render() }
            return
        }
        let ch = event.charactersIgnoringModifiers.lowercased()
        guard ch.count == 1 else { return }
        switch LabelMatcher.match(typed: typed + ch, labels: labels) {
        case .none:
            return
        case .partial:
            typed += ch
            render()
        case .exact(let label):
            guard let index = labels.firstIndex(of: label) else { return }
            activate(targets[index], kind: event.clickKind)
        }
    }

    private func handleSearch(_ event: KeyEvent) {
        if event.isBackspace {
            if !query.isEmpty { query.removeLast(); updateMatches(); render() }
            return
        }
        if event.isReturn {
            if let first = matches.first { activate(targets[first], kind: event.clickKind) }
            return
        }
        let ch = event.charactersIgnoringModifiers
        if ch.count == 1, let digit = Int(ch), digit >= 1, digit <= matches.count, !event.modifiers.contains(.option) {
            activate(targets[matches[digit - 1]], kind: event.clickKind)
            return
        }
        let text = event.characters
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              !event.modifiers.contains(.command), !event.modifiers.contains(.control) else { return }
        query += text
        updateMatches()
        render()
    }

    private func updateMatches() {
        guard !query.isEmpty else { matches = []; return }
        // Scattered subsequences across long titles score below zero; drop them.
        let scored = targets.enumerated().compactMap { i, t -> (Int, Double)? in
            FuzzyMatcher.bestScore(query: query, fields: t.searchFields).flatMap { $0 > 0 ? (i, $0) : nil }
        }
        matches = scored.sorted { $0.1 > $1.1 }.prefix(Self.searchLabels.count).map(\.0)
    }

    private func activate(_ target: HintTarget, kind: ClickKind) {
        ended = true
        let raise = host.settings.raiseWindowOnClick && target.pid != 0 && target.pid != host.app.processIdentifier
        host.finish()
        // Let the event tap release before the click lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            Clicker.click(target, kind: kind, raise: raise)
            // The click usually changes the screen; re-read it once it settles.
            if let app = NSWorkspace.shared.frontmostApplication { ScreenTextPrewarmer.shared.schedule(app, after: 0.8) }
        }
    }

    private func render() {
        var scene = OverlayScene()
        if searchable {
            scene.message = query
            scene.messageIsQuery = true
            for (n, index) in matches.enumerated() {
                let t = targets[index]
                scene.hints.append(HintDrawable(label: Self.searchLabels[n], anchor: anchors[index],
                                                targetFrame: t.frame, style: n == 0 ? .selected : .normal))
            }
        } else {
            for (i, t) in targets.enumerated() where labels[i].hasPrefix(typed) {
                scene.hints.append(HintDrawable(label: labels[i], typedCount: typed.count, anchor: anchors[i], targetFrame: t.frame))
            }
        }
        host.overlay.show(scene)
    }

    func end() { ended = true }
}
