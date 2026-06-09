import AppKit
import SwiftUI
import Core

/// Window controller that hosts the real SettingsView.
final class SettingsWindowController: NSWindowController {

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BrainDump Settings"
        window.center()
        self.init(window: window)

        let settingsView = SettingsView(onDone: { [weak self] in
            self?.close()
        })
        window.contentView = NSHostingView(rootView: settingsView)
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
