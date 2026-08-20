import HelmRuntime
import XCTest
@testable import Module_Disk_Engine

/// Regression: a whole-disk scan crashed with "Negative value is not
/// representable". `dev_t` is signed and synthetic volumes report negative
/// ids; the old code converted to UInt64, which traps.
final class DeviceIDTests: XCTestCase {
    func testNegativeDeviceIdsAreRepresentable() {
        let negative = BulkWalk.DeviceID(raw: dev_t(-16777233))
        let same = BulkWalk.DeviceID(raw: dev_t(-16777233))
        XCTAssertTrue(negative.matches(same))
    }

    func testDifferentDevicesDoNotMatch() {
        XCTAssertFalse(BulkWalk.DeviceID(raw: 1).matches(BulkWalk.DeviceID(raw: 2)))
        XCTAssertFalse(BulkWalk.DeviceID(raw: -1).matches(BulkWalk.DeviceID(raw: 1)))
    }

    /// A path that cannot be stat'ed must not be treated as "same volume".
    func testUnknownNeverMatches() {
        XCTAssertFalse(BulkWalk.DeviceID.unknown.matches(BulkWalk.DeviceID(raw: 1)))
        XCTAssertFalse(BulkWalk.DeviceID(raw: 1).matches(.unknown))
        XCTAssertFalse(BulkWalk.DeviceID.unknown.matches(.unknown))
    }
}
