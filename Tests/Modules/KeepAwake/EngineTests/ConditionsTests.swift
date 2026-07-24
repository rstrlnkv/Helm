import XCTest
@testable import Module_KeepAwake_Engine

final class ConditionsTests: XCTestCase {
    func test_no_inputs_inactive() {
        XCTAssertEqual(Conditions.resolve(.init()), .inactive)
    }
    func test_manual_activates() {
        var i = Conditions.Inputs(); i.manual = true
        XCTAssertEqual(Conditions.resolve(i).isActive, true)
    }
    func test_any_auto_condition_activates_OR() {
        for kp in [\Conditions.Inputs.externalDisplay, \.onPower, \.appRunning, \.timerRunning] {
            var i = Conditions.Inputs(); i[keyPath: kp] = true
            XCTAssertTrue(Conditions.resolve(i).isActive, "\(kp) should activate")
        }
    }
    func test_active_conditions_reported() {
        var i = Conditions.Inputs(); i.externalDisplay = true; i.onPower = true
        XCTAssertEqual(Conditions.resolve(i).conditions, [.externalDisplay, .power])
    }
    func test_suppression_blocks_auto_but_not_manual() {
        var i = Conditions.Inputs(); i.onPower = true; i.suppressed = true
        XCTAssertFalse(Conditions.resolve(i).isActive)
        i.manual = true
        XCTAssertTrue(Conditions.resolve(i).isActive)
    }
}
