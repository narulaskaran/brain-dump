import AppKit
import SwiftUI

/// Placeholder settings window — real settings arrive in a future task.
final class SettingsWindowController: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BrainDump Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsPlaceholderView())
        self.init(window: window)
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        VStack {
            Text("Settings")
                .font(.title2)
            Text("Coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(width: 400, height: 300)
    }
}
