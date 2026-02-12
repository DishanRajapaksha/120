import AppKit

/// AppDelegate owns the menubar UI and orchestrates the DisplayNudger lifecycle.
///
/// Responsibilities:
/// - Create a status bar item and menu (Turn On/Off, Launch at Login, Quit)
/// - Prevent App Nap so frame timing stays accurate
/// - Start/stop the DisplayNudger (which flips a pixel each display refresh)
/// - Keep UI state (icon and menu titles) in sync

@MainActor
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Custom entrypoint for SwiftPM executable: create the NSApplication,
    /// attach the delegate, set accessory policy, and start the run loop.
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private let logger = AppLogger.shared
    private let launchAtLoginController: LaunchAtLoginController
    private let nudger: DisplayNudger
    private let systemEventMonitor = SystemEventMonitor()
    private let healthMonitor: NudgerHealthMonitor

    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var debugLoggingItem: NSMenuItem!

    private var wantsNudging = true
    private var shouldRestartAfterWake = false
    private var activity: NSObjectProtocol?

    override init() {
        self.launchAtLoginController = LaunchAtLoginController.makeDefault()
        self.nudger = DisplayNudger()
        self.healthMonitor = NudgerHealthMonitor()
        super.init()
        installCallbacks()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Make this a status bar (accessory) app.
        // This hides the Dock icon and keeps the app in the menu bar only.
        NSApp.setActivationPolicy(.accessory)

        // Prevent App Nap so the CVDisplayLink isn't deprioritized by macOS when idle.
        // Using `.latencyCritical` minimizes scheduling jitter on ProMotion displays.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .latencyCritical],
            reason: "Keep display active at high refresh rate")

        // Build status bar UI
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusIconFactory.image(isOn: true)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = "OneTwenty"

        let menu = NSMenu()
        toggleItem = NSMenuItem(
            title: "Turn Off", action: #selector(toggleNudging), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        loginItem = NSMenuItem(
            title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = launchAtLoginController.isEnabled ? .on : .off
        menu.addItem(loginItem)

        debugLoggingItem = NSMenuItem(
            title: "Debug Logging", action: #selector(toggleDebugLogging), keyEquivalent: "")
        debugLoggingItem.target = self
        debugLoggingItem.state = logger.isDebugEnabled ? .on : .off
        menu.addItem(debugLoggingItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit OneTwenty", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Start nudging immediately on launch so users see "On" by default.
        systemEventMonitor.start()
        healthMonitor.start()

        nudger.start()
        healthMonitor.setNudgerRunning(nudger.isRunning)
        updateUI()
    }

    func applicationWillTerminate(_ notification: Notification) {
        systemEventMonitor.stop()
        healthMonitor.stop()
        if let activity = activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        nudger.stop(reason: .appTermination)
    }

    // MARK: - Actions

    /// Toggle the pixel nudging on/off and refresh the UI.
    @objc private func toggleNudging() {
        wantsNudging.toggle()
        if wantsNudging {
            nudger.start()
        } else {
            nudger.stop(reason: .userRequested)
        }
        healthMonitor.setNudgerRunning(nudger.isRunning && wantsNudging)
        updateUI()
    }

    /// Toggle Launch at Login using the configured strategy controller.
    ///
    /// On failure, we surface a warning alert rather than crashing.
    @objc private func toggleLaunchAtLogin() {
        do {
            let nextState = !launchAtLoginController.isEnabled
            try launchAtLoginController.setEnabled(nextState)
            logger.info("Launch at Login set to \(nextState).")
        } catch {
            logger.error("Failed to update Launch at Login: \(error.localizedDescription)")
            // Present an alert for visibility, but don't crash
            let alert = NSAlert()
            alert.messageText = "Failed to update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
        updateUI()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleDebugLogging() {
        logger.setDebugEnabled(!logger.isDebugEnabled)
        updateUI()
    }

    // MARK: - UI

    /// Update the menu bar icon and menu item titles to match the current state.
    private func updateUI() {
        statusItem.button?.image = StatusIconFactory.image(isOn: nudger.isRunning)
        toggleItem.title = wantsNudging ? "Turn Off" : "Turn On"
        loginItem.state = launchAtLoginController.isEnabled ? .on : .off
        debugLoggingItem.state = logger.isDebugEnabled ? .on : .off
    }

    private func installCallbacks() {
        nudger.onFrameTick = { [weak self] in
            self?.healthMonitor.recordTick()
        }

        healthMonitor.onRestartRequested = { [weak self] in
            guard let self, self.wantsNudging else { return }
            self.nudger.restart(reason: .healthMonitor)
            self.healthMonitor.setNudgerRunning(self.nudger.isRunning)
            self.updateUI()
        }

        systemEventMonitor.onWillSleep = { [weak self] in
            self?.handleSystemWillSleep()
        }

        systemEventMonitor.onDidWake = { [weak self] in
            self?.handleSystemDidWake()
        }

        systemEventMonitor.onScreenParametersChanged = { [weak self] in
            self?.handleScreenParametersChanged()
        }
    }

    private func handleSystemWillSleep() {
        logger.info("System will sleep.")
        shouldRestartAfterWake = wantsNudging
        nudger.stop(reason: .systemWillSleep)
        healthMonitor.setNudgerRunning(false)
        updateUI()
    }

    private func handleSystemDidWake() {
        logger.info("System did wake.")
        guard shouldRestartAfterWake, wantsNudging else { return }
        nudger.restart(reason: .systemDidWake)
        healthMonitor.setNudgerRunning(nudger.isRunning)
        updateUI()
    }

    private func handleScreenParametersChanged() {
        logger.info("Screen parameters changed.")
        guard wantsNudging else { return }
        nudger.handleScreenTopologyChange()
        healthMonitor.setNudgerRunning(nudger.isRunning)
        updateUI()
    }
}
