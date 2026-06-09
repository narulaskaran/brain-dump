import AppKit
import SwiftUI
import Core

/// Owns the NSStatusItem, NSPopover, and icon-state machine.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var spinnerTimer: Timer?
    private var spinnerFrame: Int = 0
    private var doneRevertTimer: Timer?
    private var hotkeyManager: HotkeyManager?
    private var currentState: MenuBarIconState = .idle
    private var settingsWindowController: SettingsWindowController?

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover = NSPopover()
        super.init()

        configureStatusItem()
        configurePopover()
        configureMenu()

        hotkeyManager = HotkeyManager { [weak self] in
            Task { @MainActor in
                self?.togglePopover(nil)
            }
        }

        // Wire icon state transitions from the submission queue
        Task {
            await SubmissionQueue.shared.setOnStateChange { [weak self] state in
                self?.setState(state)
            }
        }

        setState(.idle)
    }

    // MARK: - Configuration

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.image = brainImage()
        button.image?.isTemplate = true
        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopover() {
        popover.contentViewController = NSHostingController(
            rootView: IdeaInputView(onSubmit: { [weak self] text in
                self?.handleSubmit(text)
            }, onDiscard: { [weak self] in
                self?.closePopover()
            })
        )
        popover.behavior = .transient
        popover.delegate = self
    }

    private func configureMenu() {
        // Menu is built on-demand when the popover is closed
    }

    // MARK: - Status Item Action

    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            // If there's an error state, clear it when user clicks
            if case .error = currentState {
                setState(.idle)
            }
            showMenu()
        }
    }

    private func showMenu() {
        let menu = buildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Remove menu so next click goes through button action
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let newIdeaItem = NSMenuItem(
            title: "New Idea",
            action: #selector(openPopoverFromMenu),
            keyEquivalent: ""
        )
        newIdeaItem.target = self
        menu.addItem(newIdeaItem)

        menu.addItem(.separator())

        let groomItem = NSMenuItem(
            title: "Groom Backlog",
            action: #selector(groomBacklog),
            keyEquivalent: ""
        )
        groomItem.target = self
        menu.addItem(groomItem)

        menu.addItem(.separator())

        let lastFiledItem = NSMenuItem(title: "Last Filed: —", action: nil, keyEquivalent: "")
        lastFiledItem.isEnabled = false
        menu.addItem(lastFiledItem)

        // Show error message in menu if in error state
        if case .error(let message) = currentState {
            menu.addItem(.separator())
            let errorItem = NSMenuItem(title: "⚠ \(message)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Menu Actions

    @objc private func openPopoverFromMenu() {
        togglePopover(nil)
    }

    @objc private func groomBacklog() {
        setState(.processing)
        Task {
            await SubmissionQueue.shared.runGrooming()
            // Final state (.done / .error) delivered via onStateChange callback.
        }
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
    }

    /// Open the Settings window automatically (e.g. on first run).
    func openSettingsIfNeeded() {
        openSettings()
    }

    /// Re-read ProviderConfig and vault URL after settings are saved.
    func reloadConfig() {
        let config = ProviderConfig.load() ?? .defaultAnthropic
        let vaultURL = VaultPathManager.effectiveVaultURL()
        print("[BrainDump] Config reloaded — provider: \(config.provider), model: \(config.model), vault: \(vaultURL.path)")
    }

    // MARK: - Popover Management

    func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover()
        } else {
            openPopover()
        }
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }

        // Refresh the content view so it starts fresh
        popover.contentViewController = NSHostingController(
            rootView: IdeaInputView(onSubmit: { [weak self] text in
                self?.handleSubmit(text)
            }, onDiscard: { [weak self] in
                self?.closePopover()
            })
        )

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover.performClose(nil)
    }

    // MARK: - Submission

    private func handleSubmit(_ text: String) {
        closePopover()
        // .processing state is pushed by SubmissionQueue.onStateChange;
        // set it immediately here too so the icon updates without delay.
        setState(.processing)
        Task {
            await SubmissionQueue.shared.submit(text)
            // Final state (.done / .error) is delivered via onStateChange callback.
        }
    }

    // MARK: - Icon State Machine

    func setState(_ state: MenuBarIconState) {
        // Cancel any running animations/timers
        spinnerTimer?.invalidate()
        spinnerTimer = nil
        doneRevertTimer?.invalidate()
        doneRevertTimer = nil

        currentState = state

        switch state {
        case .idle:
            setButtonImage(brainImage(), isTemplate: true)

        case .processing:
            startSpinner()

        case .done:
            setButtonImage(sfSymbol("lightbulb"), isTemplate: true)
            doneRevertTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.setState(.idle)
                }
            }

        case .error:
            setButtonImage(sfSymbol("exclamationmark.triangle"), isTemplate: true)
        }
    }

    private func startSpinner() {
        spinnerFrame = 0
        updateSpinnerFrame()
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSpinnerFrame()
            }
        }
    }

    private func updateSpinnerFrame() {
        spinnerFrame = (spinnerFrame + 1) % 8
        // Rotate the spinner symbol by applying a rotation transform based on frame
        let angle = Double(spinnerFrame) / 8.0 * 2.0 * Double.pi
        guard let button = statusItem.button else { return }

        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let baseImage = self.sfSymbol("arrow.2.circlepath") else { return false }
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: angle)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
            baseImage.draw(in: rect)
            return true
        }
        image.isTemplate = true
        button.image = image
    }

    private func setButtonImage(_ image: NSImage?, isTemplate: Bool) {
        guard let button = statusItem.button else { return }
        image?.isTemplate = isTemplate
        button.image = image
    }

    // MARK: - Image Helpers

    private func brainImage() -> NSImage? {
        // Try known SF Symbol names for a brain icon
        let candidates = ["brain.head.profile", "brain", "brain.filled.head.profile"]
        for name in candidates {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: "BrainDump") {
                return img
            }
        }
        // Fallback: plain circle
        return sfSymbol("circle") ?? NSImage()
    }

    private func sfSymbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidClose(_ notification: Notification) {
        // Nothing to do for now
    }
}
