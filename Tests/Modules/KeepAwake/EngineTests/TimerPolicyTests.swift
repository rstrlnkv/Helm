import XCTest
@testable import Module_KeepAwake_Engine

final class TimerPolicyTests: XCTestCase {
    func test_no_auto_condition_deactivates() {
        XCTAssertEqual(TimerPolicy.onExpiry(hasAutoCondition: false, suppressed: false), .deactivate)
    }
    func test_auto_condition_not_suppressed_continues_as_auto() {
        XCTAssertEqual(TimerPolicy.onExpiry(hasAutoCondition: true, suppressed: false), .continueAsAuto)
    }
    func test_auto_condition_suppressed_deactivates() {
        XCTAssertEqual(TimerPolicy.onExpiry(hasAutoCondition: true, suppressed: true), .deactivate)
    }
}
