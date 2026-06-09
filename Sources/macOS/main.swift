import AppKit

// Standard NSApplication entry point for a menu-bar-only app.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
