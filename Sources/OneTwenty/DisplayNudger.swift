import AppKit
import CoreVideo

enum NudgerStopReason: String {
    case userRequested
    case appTermination
    case systemWillSleep
    case restarting
}

enum NudgerRestartReason: String {
    case systemDidWake
    case screenTopologyChanged
    case healthMonitor
    case manual
}

struct DisplayTargetSelector {
    static func select(
        windowDisplayID: CGDirectDisplayID?,
        fallbackDisplayID: CGDirectDisplayID
    ) -> CGDirectDisplayID {
        windowDisplayID ?? fallbackDisplayID
    }
}

struct NudgeWindowPlacement {
    static func frame(for screenFrame: CGRect?) -> CGRect {
        guard let screenFrame else {
            // Last-resort location if no screen is currently attached.
            return CGRect(x: -10_000, y: -10_000, width: 1, height: 1)
        }

        // Keep the nudge in a stable, always-onscreen location away from corners.
        return CGRect(x: screenFrame.minX + 24, y: screenFrame.minY + 24, width: 1, height: 1)
    }
}

/// DisplayNudger keeps the display in a high refresh mode by flipping a tiny pixel
/// at the screen refresh cadence using CVDisplayLink.
///
/// It owns a 1×1 borderless window placed near the screen corner, with a custom
/// PixelView that alternates a nearly transparent fill. This triggers composition
/// work without producing visible artifacts.
@MainActor
final class DisplayNudger {
    private(set) var isRunning: Bool = false
    var onFrameTick: (() -> Void)?

    private let window: NSWindow
    private let logger: AppLogger
    private let pixelView = PixelView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    private let retrySchedule: [TimeInterval] = [0.5, 1.0, 2.0]

    private var pendingRetry: DispatchWorkItem?
    private var retryCount = 0
    private var tickSampleStartedAt: CFAbsoluteTime = 0
    private var tickSampleCount: Int = 0

    init(logger: AppLogger = .shared) {
        self.logger = logger

        // Create a tiny, virtually invisible window.
        let rect = NSRect(x: -10_000, y: -10_000, width: 1, height: 1)
        self.window = NSWindow(
            contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        self.window.isOpaque = false
        self.window.backgroundColor = .clear
        self.window.hasShadow = false
        self.window.ignoresMouseEvents = true
        self.window.level = .statusBar  // keep above normal windows so it's not hidden
        self.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.window.isReleasedWhenClosed = false

        self.pixelView.onTick = { [weak self] in
            self?.handleTick()
        }
        self.window.contentView = pixelView
    }

    /// Show the window, start the display link, and bind it to the window's display.
    func start() {
        guard !isRunning else { return }

        pendingRetry?.cancel()
        positionWindow()
        window.orderFrontRegardless()

        guard pixelView.start() else {
            logger.error("Failed to start CVDisplayLink.")
            window.orderOut(nil)
            scheduleRetry()
            return
        }

        retryCount = 0
        tickSampleStartedAt = CFAbsoluteTimeGetCurrent()
        tickSampleCount = 0
        retargetDisplayLink()
        isRunning = true
        logger.info("Display nudger started.")
    }

    /// Stop the display link and hide the window.
    func stop(reason: NudgerStopReason) {
        pendingRetry?.cancel()
        pendingRetry = nil
        retryCount = 0

        guard isRunning || pixelView.hasDisplayLink else { return }
        pixelView.stop()
        window.orderOut(nil)
        isRunning = false
        logger.info("Display nudger stopped (reason: \(reason.rawValue)).")
    }

    func restart(reason: NudgerRestartReason) {
        logger.info("Display nudger restarting (reason: \(reason.rawValue)).")
        stop(reason: .restarting)
        start()
    }

    /// Handles display topology updates (monitor attach/detach, mode changes).
    /// If running, we restart to force the display link onto a fresh target.
    func handleScreenTopologyChange() {
        positionWindow()
        guard isRunning else {
            start()
            return
        }
        restart(reason: .screenTopologyChanged)
    }

    private func retargetDisplayLink() {
        let fallbackDisplayID = CGMainDisplayID()
        let selectedID = DisplayTargetSelector.select(
            windowDisplayID: window.screenDisplayID,
            fallbackDisplayID: fallbackDisplayID
        )

        if window.screenDisplayID == nil {
            logger.warning("No window-attached display ID; using main display fallback (\(selectedID)).")
        }

        let result = pixelView.updateDisplayLinkTarget(displayID: selectedID)
        if result != kCVReturnSuccess {
            logger.warning("Failed to retarget CVDisplayLink (CVReturn \(result)).")
            return
        }

        if let mode = CGDisplayCopyDisplayMode(selectedID) {
            logger.info(
                String(
                    format: "Target display id: %u (mode refresh: %.1f Hz)",
                    selectedID,
                    mode.refreshRate
                )
            )
        } else {
            logger.info("Target display id: \(selectedID) (mode refresh unavailable)")
        }
    }

    private func positionWindow() {
        let targetScreen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        let targetFrame = NudgeWindowPlacement.frame(for: targetScreen?.frame)
        window.setFrame(targetFrame, display: false)
    }

    private func scheduleRetry() {
        guard retryCount < retrySchedule.count else {
            logger.error("CVDisplayLink start retries exhausted.")
            return
        }

        let delay = retrySchedule[retryCount]
        retryCount += 1
        logger.warning("Retrying nudger start in \(delay)s.")

        let workItem = DispatchWorkItem { [weak self] in
            self?.start()
        }
        pendingRetry = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func handleTick() {
        onFrameTick?()
        guard isRunning else { return }

        tickSampleCount += 1
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - tickSampleStartedAt
        guard elapsed >= 5 else { return }

        let fps = Double(tickSampleCount) / elapsed
        logger.info(String(format: "Display tick rate estimate: %.1f fps", fps))
        tickSampleStartedAt = now
        tickSampleCount = 0
    }

    deinit {
        pendingRetry?.cancel()
    }
}

/// PixelView hosts a CVDisplayLink that calls back at the display's refresh rate.
/// Each tick toggles a boolean, and draw(_:) fills with extremely low alpha to
/// ensure compositing occurs while remaining visually imperceptible.
private final class PixelView: NSView {
    // Use the smallest non-zero 8-bit alpha step so the pixel is still effectively
    // invisible but not quantized to fully transparent by the compositor.
    private static let nudgeAlpha: CGFloat = 1.0 / 255.0

    private var link: CVDisplayLink?
    private var flip = false
    var onTick: (() -> Void)?

    var hasDisplayLink: Bool {
        link != nil
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.isOpaque = false
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Create and start a CVDisplayLink.
    /// We use the C callback to hop back onto main for view updates.
    @discardableResult
    func start() -> Bool {
        guard link == nil else { return true }

        var newLink: CVDisplayLink?
        let creationResult = CVDisplayLinkCreateWithActiveCGDisplays(&newLink)
        guard creationResult == kCVReturnSuccess, let dl = newLink else { return false }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userData in
            let mySelf = Unmanaged<PixelView>.fromOpaque(userData!).takeUnretainedValue()
            mySelf.tick()
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(
            dl, callback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))

        self.link = dl
        let startResult = CVDisplayLinkStart(dl)
        if startResult != kCVReturnSuccess {
            link = nil
            return false
        }
        return true
    }

    /// Stop and release the CVDisplayLink.
    func stop() {
        guard let dl = link else { return }
        CVDisplayLinkStop(dl)
        link = nil
    }

    /// Retarget the display link to a specific CGDirectDisplayID.
    /// Call after starting to ensure CVDisplayLink exists.
    @discardableResult
    func updateDisplayLinkTarget(displayID: CGDirectDisplayID) -> CVReturn {
        guard let dl = link else { return kCVReturnError }
        return CVDisplayLinkSetCurrentCGDisplay(dl, displayID)
    }

    private func tick() {
        flip.toggle()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let color = self.flip
                ? NSColor.white.withAlphaComponent(Self.nudgeAlpha)
                : NSColor.black.withAlphaComponent(Self.nudgeAlpha)
            self.layer?.backgroundColor = color.cgColor
            self.onTick?()
            self.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Alternate two near-transparent colors to trigger composition with no visible artifact.
        let c: NSColor =
            flip
            ? NSColor.white.withAlphaComponent(Self.nudgeAlpha)
            : NSColor.black.withAlphaComponent(Self.nudgeAlpha)
        c.setFill()
        dirtyRect.fill()
    }
}

extension NSWindow {
    /// The CGDirectDisplayID associated with the window's current screen.
    var screenDisplayID: CGDirectDisplayID? {
        guard let screen = self.screen else { return nil }
        let desc = screen.deviceDescription
        if let id = (desc[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value {
            return CGDirectDisplayID(id)
        }
        return nil
    }
}
