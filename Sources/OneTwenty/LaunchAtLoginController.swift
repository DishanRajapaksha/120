import Foundation
import ServiceManagement

enum LaunchAtLoginStrategy: String, Equatable {
    case smAppService
    case launchAgent
}

struct LaunchAtLoginContext {
    let isBundledApp: Bool
    let osMajorVersion: Int

    static var current: LaunchAtLoginContext {
        LaunchAtLoginContext(
            isBundledApp: Bundle.main.bundleURL.pathExtension.lowercased() == "app",
            osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        )
    }
}

enum LaunchAtLoginStrategySelector {
    static func preferredOrder(for context: LaunchAtLoginContext) -> [LaunchAtLoginStrategy] {
        if context.isBundledApp, context.osMajorVersion >= 13 {
            return [.smAppService, .launchAgent]
        }
        return [.launchAgent]
    }
}

protocol LaunchAtLoginManaging: AnyObject {
    var strategy: LaunchAtLoginStrategy { get }
    var isSupported: Bool { get }
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LaunchAtLoginControllerError: LocalizedError {
    case enableFailed([Error])
    case disableFailed([Error])

    var errorDescription: String? {
        switch self {
        case .enableFailed(let errors):
            return "Unable to enable Launch at Login. " + joinedDescription(errors)
        case .disableFailed(let errors):
            return "Unable to disable Launch at Login. " + joinedDescription(errors)
        }
    }

    private func joinedDescription(_ errors: [Error]) -> String {
        errors.map(\.localizedDescription).joined(separator: " | ")
    }
}

final class LaunchAtLoginController {
    private let managers: [LaunchAtLoginManaging]
    private let logger: AppLogger

    init(managers: [LaunchAtLoginManaging], logger: AppLogger = .shared) {
        self.managers = managers
        self.logger = logger
    }

    static func makeDefault(logger: AppLogger = .shared) -> LaunchAtLoginController {
        let context = LaunchAtLoginContext.current
        let strategies = LaunchAtLoginStrategySelector.preferredOrder(for: context)

        let strategyManagers: [LaunchAtLoginStrategy: LaunchAtLoginManaging] = [
            .smAppService: SMAppServiceLaunchController(isBundledApp: context.isBundledApp),
            .launchAgent: LaunchAgentLaunchController(),
        ]

        let orderedManagers = strategies.compactMap { strategyManagers[$0] }
        return LaunchAtLoginController(managers: orderedManagers, logger: logger)
    }

    var isEnabled: Bool {
        managers.contains { $0.isEnabled }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try enable()
        } else {
            try disable()
        }
    }

    private func enable() throws {
        var failures: [Error] = []

        for manager in managers where manager.isSupported {
            do {
                try manager.setEnabled(true)
                logger.info("Launch at Login enabled via \(manager.strategy.rawValue).")
                disableOtherManagers(except: manager.strategy)
                return
            } catch {
                failures.append(error)
                logger.warning(
                    "Failed to enable Launch at Login via \(manager.strategy.rawValue): \(error.localizedDescription)"
                )
            }
        }

        throw LaunchAtLoginControllerError.enableFailed(failures)
    }

    private func disable() throws {
        var failures: [Error] = []

        for manager in managers where manager.isSupported && manager.isEnabled {
            do {
                try manager.setEnabled(false)
                logger.info("Launch at Login disabled via \(manager.strategy.rawValue).")
            } catch {
                failures.append(error)
                logger.warning(
                    "Failed to disable Launch at Login via \(manager.strategy.rawValue): \(error.localizedDescription)"
                )
            }
        }

        if !failures.isEmpty {
            throw LaunchAtLoginControllerError.disableFailed(failures)
        }
    }

    private func disableOtherManagers(except strategy: LaunchAtLoginStrategy) {
        for manager in managers where manager.strategy != strategy && manager.isSupported && manager.isEnabled {
            do {
                try manager.setEnabled(false)
            } catch {
                logger.warning(
                    "Failed to disable fallback Launch at Login manager \(manager.strategy.rawValue): \(error.localizedDescription)"
                )
            }
        }
    }
}

final class SMAppServiceLaunchController: LaunchAtLoginManaging {
    let strategy: LaunchAtLoginStrategy = .smAppService
    private let isBundledApp: Bool

    init(isBundledApp: Bool = Bundle.main.bundleURL.pathExtension.lowercased() == "app") {
        self.isBundledApp = isBundledApp
    }

    var isSupported: Bool {
        guard isBundledApp else { return false }
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    var isEnabled: Bool {
        guard isSupported else { return false }
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            return status == .enabled || status == .requiresApproval
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isSupported else {
            throw NSError(
                domain: "LaunchAtLoginController",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "SMAppService is unavailable for the current runtime context."
                ]
            )
        }

        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}

final class LaunchAgentLaunchController: LaunchAtLoginManaging {
    let strategy: LaunchAtLoginStrategy = .launchAgent

    var isSupported: Bool {
        true
    }

    var isEnabled: Bool {
        LoginItemManager.isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        try LoginItemManager.setEnabled(enabled)
    }
}
