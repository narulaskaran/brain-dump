import AppKit
import Core

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only app: no dock icon
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController()

        // First-run: open Settings if no API key has been saved yet
        if KeychainHelper.load(key: "apiKey") == nil {
            statusBarController?.openSettingsIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController = nil
    }
}
