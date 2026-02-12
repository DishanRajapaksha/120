import XCTest
@testable import OneTwenty

final class DisplayTargetSelectorTests: XCTestCase {
    func testSelectReturnsWindowDisplayIDWhenPresent() {
        let selected = DisplayTargetSelector.select(
            windowDisplayID: CGDirectDisplayID(123),
            fallbackDisplayID: CGDirectDisplayID(999)
        )
        XCTAssertEqual(selected, CGDirectDisplayID(123))
    }

    func testSelectFallsBackToMainDisplayWhenWindowDisplayMissing() {
        let selected = DisplayTargetSelector.select(
            windowDisplayID: nil,
            fallbackDisplayID: CGDirectDisplayID(999)
        )
        XCTAssertEqual(selected, CGDirectDisplayID(999))
    }
}
