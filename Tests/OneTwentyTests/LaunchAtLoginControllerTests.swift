import Foundation
import XCTest
@testable import OneTwenty

final class LaunchAtLoginControllerTests: XCTestCase {
    func testPreferredOrderUsesSMAppServiceForBundledMacOS13Plus() {
        let context = LaunchAtLoginContext(isBundledApp: true, osMajorVersion: 13)
        let order = LaunchAtLoginStrategySelector.preferredOrder(for: context)
        XCTAssertEqual(order, [.smAppService, .launchAgent])
    }

    func testPreferredOrderUsesLaunchAgentForNonBundledBuild() {
        let context = LaunchAtLoginContext(isBundledApp: false, osMajorVersion: 14)
        let order = LaunchAtLoginStrategySelector.preferredOrder(for: context)
        XCTAssertEqual(order, [.launchAgent])
    }

    func testEnableFallsBackWhenPrimaryManagerFails() throws {
        let primary = FakeLaunchManager(strategy: .smAppService)
        primary.errorForEnable = NSError(
            domain: "test", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "primary failure"]
        )

        let fallback = FakeLaunchManager(strategy: .launchAgent)
        let controller = LaunchAtLoginController(managers: [primary, fallback])

        try controller.setEnabled(true)

        XCTAssertEqual(primary.setEnabledCalls, [true])
        XCTAssertEqual(fallback.setEnabledCalls, [true])
        XCTAssertTrue(controller.isEnabled)
    }

    func testDisableDisablesEnabledManagers() throws {
        let primary = FakeLaunchManager(strategy: .smAppService, initiallyEnabled: true)
        let fallback = FakeLaunchManager(strategy: .launchAgent, initiallyEnabled: true)
        let controller = LaunchAtLoginController(managers: [primary, fallback])

        try controller.setEnabled(false)

        XCTAssertEqual(primary.setEnabledCalls, [false])
        XCTAssertEqual(fallback.setEnabledCalls, [false])
        XCTAssertFalse(controller.isEnabled)
    }
}

private final class FakeLaunchManager: LaunchAtLoginManaging {
    let strategy: LaunchAtLoginStrategy
    var isSupported: Bool = true
    var isEnabled: Bool

    var errorForEnable: Error?
    var errorForDisable: Error?
    var setEnabledCalls: [Bool] = []

    init(strategy: LaunchAtLoginStrategy, initiallyEnabled: Bool = false) {
        self.strategy = strategy
        self.isEnabled = initiallyEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        setEnabledCalls.append(enabled)
        if enabled, let errorForEnable {
            throw errorForEnable
        }
        if !enabled, let errorForDisable {
            throw errorForDisable
        }
        isEnabled = enabled
    }
}
