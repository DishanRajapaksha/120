import Foundation

enum NudgerHealthEvaluation: Equatable {
    case healthy
    case staleNeedsRestart
    case staleThrottled
}

/// Pure policy for deciding when stale frame ticks should trigger restarts.
struct NudgerHealthPolicy {
    var staleThreshold: TimeInterval
    var maxRestartsPerWindow: Int
    var restartWindow: TimeInterval

    private(set) var restartTimestamps: [Date] = []

    init(
        staleThreshold: TimeInterval = 1.0,
        maxRestartsPerWindow: Int = 3,
        restartWindow: TimeInterval = 30.0
    ) {
        self.staleThreshold = staleThreshold
        self.maxRestartsPerWindow = maxRestartsPerWindow
        self.restartWindow = restartWindow
    }

    mutating func evaluate(now: Date, lastTickAt: Date) -> NudgerHealthEvaluation {
        pruneRestartHistory(now: now)

        guard now.timeIntervalSince(lastTickAt) > staleThreshold else {
            return .healthy
        }

        guard restartTimestamps.count < maxRestartsPerWindow else {
            return .staleThrottled
        }

        restartTimestamps.append(now)
        return .staleNeedsRestart
    }

    mutating func reset() {
        restartTimestamps.removeAll()
    }

    private mutating func pruneRestartHistory(now: Date) {
        restartTimestamps.removeAll { now.timeIntervalSince($0) > restartWindow }
    }
}

/// Runtime watchdog that periodically checks display-link health and asks for a restart.
@MainActor
final class NudgerHealthMonitor {
    typealias DateProvider = () -> Date

    var onRestartRequested: (() -> Void)?

    private let checkInterval: TimeInterval
    private let now: DateProvider
    private let logger: AppLogger

    private var timer: DispatchSourceTimer?
    private var policy: NudgerHealthPolicy
    private var lastTickAt: Date
    private var nudgerRunning = false
    private var hasLoggedThrottle = false

    init(
        checkInterval: TimeInterval = 2.0,
        staleThreshold: TimeInterval = 1.0,
        maxRestartsPerWindow: Int = 3,
        restartWindow: TimeInterval = 30.0,
        now: @escaping DateProvider = Date.init,
        logger: AppLogger = .shared
    ) {
        self.checkInterval = checkInterval
        self.now = now
        self.logger = logger
        self.policy = NudgerHealthPolicy(
            staleThreshold: staleThreshold,
            maxRestartsPerWindow: maxRestartsPerWindow,
            restartWindow: restartWindow
        )
        self.lastTickAt = now()
    }

    func start() {
        guard timer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + checkInterval, repeating: checkInterval)
        timer.setEventHandler { [weak self] in
            self?.poll()
        }
        timer.resume()

        self.timer = timer
        logger.debug("Nudger health monitor started.")
    }

    func stop() {
        timer?.cancel()
        timer = nil
        logger.debug("Nudger health monitor stopped.")
    }

    func setNudgerRunning(_ running: Bool) {
        nudgerRunning = running
        if running {
            lastTickAt = now()
            policy.reset()
            hasLoggedThrottle = false
        }
    }

    func recordTick(at date: Date? = nil) {
        lastTickAt = date ?? now()
        hasLoggedThrottle = false
    }

    private func poll() {
        guard nudgerRunning else { return }

        let current = now()
        let evaluation = policy.evaluate(now: current, lastTickAt: lastTickAt)

        switch evaluation {
        case .healthy:
            hasLoggedThrottle = false
        case .staleNeedsRestart:
            logger.warning("Display tick appears stale. Requesting nudger restart.")
            onRestartRequested?()
        case .staleThrottled:
            guard !hasLoggedThrottle else { return }
            logger.warning("Display tick stale but restart is throttled.")
            hasLoggedThrottle = true
        }
    }

    deinit {
        timer?.cancel()
    }
}
