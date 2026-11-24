import XCTest
@testable import HelmUI

/// A pop-up offers a handful of values where a stored one may be any number in
/// range (the pointer nudge's interval, the battery level that ends a session),
/// so a stored value that is not offered must still be selectable: an empty
/// button invites choosing something, overwriting a setting nobody meant to touch.
final class APopUpNeverLosesTheStoredValueTests: XCTestCase {
    private let minutes = [1, 2, 5, 10, 15, 30, 60]

    func testAnOfferedValueLeavesTheListAlone() {
        XCTAssertEqual(HelmChoices.including(5, in: minutes), minutes)
    }

    /// The case the type exists for: 7 minutes, between two offered values.
    func testAStoredValueThatIsNotOfferedIsAddedInOrder() {
        XCTAssertEqual(HelmChoices.including(7, in: minutes),
                       [1, 2, 5, 7, 10, 15, 30, 60])
    }

    /// Below and above the offered range, not only between two of them.
    func testAValueOutsideTheRangeStillAppears() {
        XCTAssertEqual(HelmChoices.including(90, in: minutes).last, 90)
        XCTAssertEqual(HelmChoices.including(0, in: minutes).first, 0)
    }

    /// And it is added once, not once per call — the list is rebuilt on every
    /// redraw of the row.
    func testTheOddValueIsNotAddedTwice() {
        let once = HelmChoices.including(7, in: minutes)
        XCTAssertEqual(HelmChoices.including(7, in: once), once)
    }

    /// The battery guard's own set, whose stored values step by five: a plist
    /// written by hand is the only way to land between them, and it must not
    /// take the row down with it.
    func testTheBatteryGuardKeepsAHandEditedLevel() {
        let levels = Array(stride(from: 5, through: 50, by: 5))
        XCTAssertEqual(HelmChoices.including(23, in: levels).firstIndex(of: 23), 4)
        XCTAssertEqual(HelmChoices.including(23, in: levels).count, levels.count + 1)
    }
}
