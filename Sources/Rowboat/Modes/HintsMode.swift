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
        if searchable { render() }
        ElementCollector(options: options).collect(app: host.app) { [weak self] targets, report in
            guard let self, !self.ended else { return }
            if targets.isEmpty {
                self.host.overlay.flash(report.error == nil ? "No targets" : "No window")
                self.host.finish()
                return
            }
            self.targets = targets
            self.loaded = true
            if !self.searchable {
                self.labels = LabelGenerator(alphabet: self.host.settings.labelCharacters).labels(count: targets.count)
            }
            self.anchors = Self.anchors(for: targets, labels: self.searchable ? [] : self.labels, visible: report.visibleFrame)
            if RLog.echo, !self.searchable {
                for (i, t) in targets.enumerated() { Log.mode.info("label \(self.labels[i]) -> \(t.role) '\(t.displayName)' @\(Int(t.frame.minX)),\(Int(t.frame.minY))") }
            }
            self.render()
            let replay = self.pending
            self.pending = []
            replay.forEach(self.handle)
        }
    }

    static func anchors(for targets: [HintTarget], labels: [String], visible: CGRect) -> [CGPoint] {
        let size = OverlayTheme.labelSize(for: labels.max(by: { $0.count < $1.count }) ?? "88")
        let raw = targets.map { HintLayout.labelAnchor(for: $0.frame, labelSize: size, within: visible) }
        return HintLayout.placeLabels(anchors: raw, labelSize: size)
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
        host.finish()
        // Let the event tap release before the click lands.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            Clicker.click(target, kind: kind)
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
