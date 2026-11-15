import XCTest
@testable import Module_KeepAwake_Engine

final class BatteryGuardTests: XCTestCase {
    /// Both switches are veto: nothing about the reading can defeat them.
    func test_disabled_or_on_mains_never_trips_for_any_reading() {
        for percent in [-1, 0, 1, 50, 100, 255, Int.max, Int.min] {
            XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: false, isOnBattery: true,
                                                         percent: percent, threshold: 100))
            XCTAssertFalse(BatteryGuard.shouldDeactivate(enabled: true, isOnBattery: false,
                                                         percent: percent, threshold: 100))
        }
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
