import XCTest
@testable import Module_KeepAwake_Engine

final class PowerSupportTests: XCTestCase {
    func test_ac_power_is_on_power() {
        XCTAssertTrue(PowerSupport.isOnPower(powerSourceState: "AC Power"))
    }
    func test_battery_power_is_not_on_power() {
        XCTAssertFalse(PowerSupport.isOnPower(powerSourceState: "Battery Power"))
    }
    func test_nil_is_not_on_power() {
        XCTAssertFalse(PowerSupport.isOnPower(powerSourceState: nil))
    }
}
