import AppKit

/// Settings window built with AppKit so the project needs no SwiftUI macro
/// plugins (absent from the command line tools).
final class SettingsWindowController: NSObject, NSTextViewDelegate, NSTextFieldDelegate {
    private let window: NSWindow
    private let settings = Settings.shared
    private var controls: [() -> Void] = []   // refreshers
    private var excludedView: NSTextView!
    private var screenTextView: NSTextView!
    private var labelField: NSTextField!

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 760), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Rowboat Settings"
        window.isReleasedWhenClosed = false
        super.init()
        window.contentView = buildContent()
        window.center()
    }

    func show() {
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func refresh() { controls.forEach { $0() } }

    // MARK: layout

    private func buildContent() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(header("Shortcuts"))
        stack.addArrangedSubview(shortcutRow("Click labels", get: { self.settings.hintsShortcut }, set: { self.settings.hintsShortcut = $0 }))
        stack.addArrangedSubview(shortcutRow("Scroll", get: { self.settings.scrollShortcut }, set: { self.settings.scrollShortcut = $0 }))
        stack.addArrangedSubview(shortcutRow("Search", get: { self.settings.searchShortcut }, set: { self.settings.searchShortcut = $0 }))
        stack.addArrangedSubview(caption("Click a box, then press the keys; press Delete instead to leave a mode without a shortcut (it stays in the menu bar menu). A hyper key from Raycast or Karabiner records as ⌃⌥⇧⌘ plus the key. Press a shortcut again to leave a mode; Escape always leaves."))

        stack.addArrangedSubview(header("Labels"))
        labelField = NSTextField(string: settings.labelCharacters)
        labelField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        labelField.delegate = self
        labelField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        stack.addArrangedSubview(labelled("Label characters", labelField))
        stack.addArrangedSubview(toggle("Label text and images too, not only controls", get: { self.settings.labelTextAndImages }, set: { self.settings.labelTextAndImages = $0 }))
        stack.addArrangedSubview(toggle("Label every visible window, not only the active one", get: { self.settings.labelAllWindows }, set: { self.settings.labelAllWindows = $0 }))
        stack.addArrangedSubview(toggle("Clicking into another window brings it to the front", get: { self.settings.raiseWindowOnClick }, set: { self.settings.raiseWindowOnClick = $0 }))
        stack.addArrangedSubview(caption("Home row first. Shift on the last letter right-clicks, ⌘ command-clicks, ⌥ double-clicks, ⌃ middle-clicks."))

        stack.addArrangedSubview(header("Scrolling"))
        stack.addArrangedSubview(sliderRow("Speed", min: 300, max: 4000, format: { "\(Int($0)) px/s" },
                                           get: { self.settings.scrollPixelsPerSecond }, set: { self.settings.scrollPixelsPerSecond = $0 }))
        stack.addArrangedSubview(sliderRow("Shift dash", min: 1, max: 6, format: { String(format: "%.1f×", $0) },
                                           get: { self.settings.dashMultiplier }, set: { self.settings.dashMultiplier = $0 }))
        stack.addArrangedSubview(toggle("Arrow keys scroll too", get: { self.settings.arrowKeysScroll }, set: { self.settings.arrowKeysScroll = $0 }))
        stack.addArrangedSubview(toggle("Move the cursor to the scroll area", get: { self.settings.warpCursorInScrollMode }, set: { self.settings.warpCursorInScrollMode = $0 }))
        stack.addArrangedSubview(popupRow("Leave scroll mode after", options: [("Never", 0), ("3 seconds", 3), ("5 seconds", 5), ("10 seconds", 10)],
                                          get: { self.settings.scrollAutoDeactivateSeconds }, set: { self.settings.scrollAutoDeactivateSeconds = $0 }))

        stack.addArrangedSubview(header("Apps"))
        stack.addArrangedSubview(toggle("Switch on accessibility in Chromium and Electron apps",
                                        get: { self.settings.enableChromiumAccessibility }, set: { self.settings.enableChromiumAccessibility = $0 }))
        stack.addArrangedSubview(caption("Chrome, Arc, Brave, Edge, VS Code, Slack, Discord and others expose their contents only when asked. Restart an app after turning this on."))
        let scroll = NSScrollView()
        excludedView = NSTextView()
        excludedView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        excludedView.delegate = self
        excludedView.isRichText = false
        excludedView.autoresizingMask = [.width]
        excludedView.string = settings.excludedBundleIdentifiers.joined(separator: "\n")
        scroll.documentView = excludedView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 64).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 500).isActive = true
        stack.addArrangedSubview(labelled("Excluded bundle identifiers, one per line", scroll, vertical: true))

        stack.addArrangedSubview(header("Screen text"))
        stack.addArrangedSubview(toggle("Read text off the screen when an app exposes almost nothing", get: { self.settings.screenTextFallback }, set: { self.settings.screenTextFallback = $0 }))
        stack.addArrangedSubview(caption("Needs the Screen Recording permission. Warp, canvases and other custom-drawn apps get labels on their text this way; the first press in such an app takes about a quarter second, later presses reuse the result until the screen changes."))
        let appsScroll = NSScrollView()
        screenTextView = NSTextView()
        screenTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        screenTextView.delegate = self
        screenTextView.isRichText = false
        screenTextView.autoresizingMask = [.width]
        screenTextView.string = settings.screenTextApps.joined(separator: "\n")
        appsScroll.documentView = screenTextView
        appsScroll.hasVerticalScroller = true
        appsScroll.borderType = .bezelBorder
        appsScroll.translatesAutoresizingMaskIntoConstraints = false
        appsScroll.heightAnchor.constraint(equalToConstant: 48).isActive = true
        appsScroll.widthAnchor.constraint(equalToConstant: 500).isActive = true
        stack.addArrangedSubview(labelled("Always use screen text in these apps (bundle identifiers)", appsScroll, vertical: true))

        stack.addArrangedSubview(header("General"))
        stack.addArrangedSubview(toggle("Show menu bar icon", get: { self.settings.showMenuBarIcon }, set: { self.settings.showMenuBarIcon = $0 }))
        stack.addArrangedSubview(toggle("Launch at login", get: { self.settings.launchAtLogin }, set: { self.settings.launchAtLogin = $0 }))
        stack.addArrangedSubview(toggle("Return the cursor after a synthetic click", get: { self.settings.restoreCursorAfterClick }, set: { self.settings.restoreCursorAfterClick = $0 }))
        let grant = NSButton(title: "Grant Accessibility Access…", target: self, action: #selector(grantAccess))
        controls.append { grant.isHidden = Permissions.accessibilityTrusted(prompt: false) }
        stack.addArrangedSubview(grant)

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    // MARK: control builders

    private func header(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 13)
        return label
    }

    private func caption(_ text: String) -> NSView {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 500
        return label
    }

    private func labelled(_ title: String, _ control: NSView, vertical: Bool = false) -> NSView {
        let label = NSTextField(labelWithString: title)
        let row = NSStackView(views: [label, control])
        row.orientation = vertical ? .vertical : .horizontal
        row.alignment = vertical ? .leading : .centerY
        row.spacing = 8
        return row
    }

    private func shortcutRow(_ title: String, get: @escaping () -> KeyShortcut?, set: @escaping (KeyShortcut?) -> Void) -> NSView {
        let recorder = ShortcutRecorderView()
        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.widthAnchor.constraint(equalToConstant: 170).isActive = true
        recorder.heightAnchor.constraint(equalToConstant: 26).isActive = true
        recorder.onRecord = { set($0); recorder.shortcut = $0 }
        controls.append { recorder.shortcut = get() }
        recorder.shortcut = get()
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [label, recorder])
        row.spacing = 8
        return row
    }

    private func toggle(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> NSView {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = get() ? .on : .off
        let action = ActionTarget { set(button.state == .on) }
        button.target = action
        button.action = #selector(ActionTarget.fire)
        retained.append(action)
        controls.append { button.state = get() ? .on : .off }
        return button
    }

    private func sliderRow(_ title: String, min: Double, max: Double, format: @escaping (Double) -> String,
                           get: @escaping () -> Double, set: @escaping (Double) -> Void) -> NSView {
        let slider = NSSlider(value: get(), minValue: min, maxValue: max, target: nil, action: nil)
        slider.widthAnchor.constraint(equalToConstant: 240).isActive = true
        let value = NSTextField(labelWithString: format(get()))
        value.widthAnchor.constraint(equalToConstant: 80).isActive = true
        let action = ActionTarget { set(slider.doubleValue); value.stringValue = format(slider.doubleValue) }
        slider.target = action
        slider.action = #selector(ActionTarget.fire)
        retained.append(action)
        controls.append { slider.doubleValue = get(); value.stringValue = format(get()) }
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [label, slider, value])
        row.spacing = 8
        return row
    }

    private func popupRow(_ title: String, options: [(String, Double)], get: @escaping () -> Double, set: @escaping (Double) -> Void) -> NSView {
        let popup = NSPopUpButton()
        for (name, _) in options { popup.addItem(withTitle: name) }
        let select = { popup.selectItem(at: options.firstIndex { $0.1 == get() } ?? 0) }
        select()
        let action = ActionTarget { set(options[popup.indexOfSelectedItem].1) }
        popup.target = action
        popup.action = #selector(ActionTarget.fire)
        retained.append(action)
        controls.append(select)
        return labelled(title, popup)
    }

    private var retained: [ActionTarget] = []

    @objc private func grantAccess() {
        _ = Permissions.accessibilityTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: text delegates

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) == labelField else { return }
        settings.labelCharacters = labelField.stringValue
    }

    func textDidChange(_ notification: Notification) {
        let lines = { (view: NSTextView) in
            view.string.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        if (notification.object as? NSTextView) == screenTextView {
            settings.screenTextApps = lines(screenTextView)
        } else {
            settings.excludedBundleIdentifiers = lines(excludedView)
        }
    }
}

final class ActionTarget: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

/// Click, then press a key combination. Escape cancels recording.
final class ShortcutRecorderView: NSView {
    var shortcut: KeyShortcut? { didSet { needsDisplay = true } }
    var onRecord: ((KeyShortcut?) -> Void)?
    private var recording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); recording = true }
    override func resignFirstResponder() -> Bool { recording = false; return true }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; window?.makeFirstResponder(nil); return }
        if event.keyCode == 51 || event.keyCode == 117 {  // Delete clears the shortcut
            onRecord?(nil); recording = false; window?.makeFirstResponder(nil); return
        }
        let mods = event.modifierFlags.intersection(KeyShortcut.relevantFlags)
        guard !mods.isEmpty || KeyNames.special[event.keyCode] != nil else { return }
        onRecord?(KeyShortcut(keyCode: event.keyCode, modifiers: mods))
        recording = false
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        let text = recording ? "Press keys…" : (shortcut?.displayString ?? "None")
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
