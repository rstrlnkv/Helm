import XCTest
@testable import Module_KeepAwake_Engine

final class BatteryGuardTests: XCTestCase {
    func test_disabled_never_deactivates() {
        XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: false, isOnBattery: true, percent: 5, threshold: 20))
    }
    func test_on_power_never_deactivates() {
        XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: false, percent: 5, threshold: 20))
    }
    func test_enabled_on_battery_below_threshold_deactivates() {
        XCTAssertTrue(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true, percent: 15, threshold: 20))
    }
    func test_enabled_on_battery_above_threshold_does_not_deactivate() {
        XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true, percent: 25, threshold: 20))
    }
    func test_boundary_at_threshold_deactivates() {
        XCTAssertTrue(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: true, percent: 20, threshold: 20))
    }
}
