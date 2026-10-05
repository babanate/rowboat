import AppKit

final class StatusItemController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    private let modes: ModeController
    private let openSettings: () -> Void

    init(modes: ModeController, openSettings: @escaping () -> Void) {
        self.modes = modes
        self.openSettings = openSettings
        super.init()
        update()
    }

    func update() {
        if Settings.shared.showMenuBarIcon {
            if item == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Rowboat")
                item.menu = buildMenu()
                self.item = item
            }
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let s = Settings.shared
        menu.addItem(modeItem("Click labels", s.hintsShortcut, #selector(hints)))
        menu.addItem(modeItem("Scroll", s.scrollShortcut, #selector(scroll)))
        menu.addItem(modeItem("Search", s.searchShortcut, #selector(search)))
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = s.launchAtLogin ? .on : .off
        menu.addItem(login)
        if !Permissions.accessibilityTrusted(prompt: false) {
            let warn = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grant), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Rowboat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func modeItem(_ title: String, _ shortcut: KeyShortcut?, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "\(title)    \(shortcut?.displayString ?? "")", action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    // Menu actions fire after the menu closes, so the previous app is frontmost again.
    @objc private func hints() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.modes.activate(.hints) } }
    @objc private func scroll() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.modes.activate(.scroll) } }
    @objc private func search() { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.modes.activate(.search) } }
    @objc private func settingsAction() { openSettings() }
    @objc private func toggleLogin() { Settings.shared.launchAtLogin.toggle() }
    @objc private func grant() {
        _ = Permissions.accessibilityTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
