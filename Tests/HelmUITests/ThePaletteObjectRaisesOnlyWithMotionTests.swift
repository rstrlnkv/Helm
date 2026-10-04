import XCTest
@testable import HelmUI

/// **The editor palette's chosen object travels up unless Reduce Motion says stillness.**
/// `PaletteObject` reads `HelmMotion.travels(reduceMotion:)` to choose between the
/// `interface` curve and no animation at all, so under the setting the object stands raised
/// at once — a decision made of an argument, asserted here for both values and not for the
/// one this Mac happens to have.
final class ThePaletteObjectRaisesOnlyWithMotionTests: XCTestCase {
    func testTheObjectTravelsWithMotionOn() {
        XCTAssertTrue(HelmMotion.travels(reduceMotion: false))
    }

    func testReduceMotionPlacesTheObjectAtOnce() {
        XCTAssertFalse(HelmMotion.travels(reduceMotion: true))
    }
}
