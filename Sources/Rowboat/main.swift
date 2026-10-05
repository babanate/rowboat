import AppKit

// Entry point. With arguments, run the developer CLI and exit; otherwise run
// the menu bar app.
if CommandLine.arguments.count > 1 {
    exit(CLI.run(Array(CommandLine.arguments.dropFirst())))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
