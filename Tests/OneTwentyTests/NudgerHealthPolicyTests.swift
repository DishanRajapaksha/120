import Foundation
import XCTest
@testable import OneTwenty

final class NudgerHealthPolicyTests: XCTestCase {
    func testHealthyWhenTickIsRecent() {
        var policy = NudgerHealthPolicy(
            staleThreshold: 1.0,
            maxRestartsPerWindow: 2,
            restartWindow: 30.0
        )

        let now = Date(timeIntervalSince1970: 100)
        let evaluation = policy.evaluate(now: now, lastTickAt: now.addingTimeInterval(-0.5))
        XCTAssertEqual(evaluation, .healthy)
    }

    func testRestartIsRequestedThenThrottled() {
        var policy = NudgerHealthPolicy(
            staleThreshold: 1.0,
            maxRestartsPerWindow: 1,
            restartWindow: 30.0
        )

        let lastTick = Date(timeIntervalSince1970: 100)

        XCTAssertEqual(
            policy.evaluate(now: Date(timeIntervalSince1970: 102), lastTickAt: lastTick),
            .staleNeedsRestart
        )
        XCTAssertEqual(
            policy.evaluate(now: Date(timeIntervalSince1970: 103), lastTickAt: lastTick),
            .staleThrottled
        )
    }

    func testRestartAllowedAgainAfterThrottleWindowExpires() {
        var policy = NudgerHealthPolicy(
            staleThreshold: 1.0,
            maxRestartsPerWindow: 1,
            restartWindow: 10.0
        )

        let lastTick = Date(timeIntervalSince1970: 100)
        XCTAssertEqual(
            policy.evaluate(now: Date(timeIntervalSince1970: 102), lastTickAt: lastTick),
            .staleNeedsRestart
        )
        XCTAssertEqual(
            policy.evaluate(now: Date(timeIntervalSince1970: 103), lastTickAt: lastTick),
            .staleThrottled
        )
        XCTAssertEqual(
            policy.evaluate(now: Date(timeIntervalSince1970: 113), lastTickAt: lastTick),
            .staleNeedsRestart
        )
    }
}
