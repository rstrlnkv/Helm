import XCTest
@testable import HelmUI

/// The arithmetic behind the Clock-shaped duration field.
///
/// It looks like nothing — divide by sixty, multiply by sixty — and it is the
/// part that can be wrong in a way nobody sees. A plist hands over a number no
/// session could have produced; somebody pastes into the hours box; either
/// column holds a negative. Every one of those has to come out as a duration
/// this module can actually start.
final class ADurationTypedInTwoColumnsTests: XCTestCase {

    private let day = 24 * 60

    // MARK: - Splitting

    /// The number that came off disk. `SessionRestore` already refuses a
    /// deadline past the ceiling; this is the same refusal one layer out, so a
    /// field cannot draw a state the engine would not accept.
    func testADurationPastTheCeilingIsBroughtDownBeforeItIsDrawn() {
        let parts = HelmDurationField.Parts.split(700 * 60, ceiling: day)
        XCTAssertEqual(parts.hours, 24)
        XCTAssertEqual(parts.minutes, 0, "a 700-hour field was drawable")
    }

    func testANegativeDurationIsZero() {
        let parts = HelmDurationField.Parts.split(-5, ceiling: day)
        XCTAssertEqual(parts.hours, 0)
        XCTAssertEqual(parts.minutes, 0)
    }

    // MARK: - Putting it back

    func testTheCeilingIsAppliedToTheSum() {
        XCTAssertEqual(HelmDurationField.Parts.total(hours: 30, minutes: 0, ceiling: day), day)
        XCTAssertEqual(HelmDurationField.Parts.total(hours: 23, minutes: 400, ceiling: day), day)
    }

    /// A pasted number must not be a crash. `hours * 60` on `Int.max` traps,
    /// and a trap here is the app terminating while somebody is typing.
    func testAnAbsurdNumberInTheHoursColumnDoesNotOverflow() {
        XCTAssertEqual(HelmDurationField.Parts.total(hours: Int.max, minutes: 0, ceiling: day), day)
        XCTAssertEqual(HelmDurationField.Parts.total(hours: Int.max, minutes: Int.max,
                                                     ceiling: day), day)
    }

    func testNegativesInEitherColumnAreZero() {
        XCTAssertEqual(HelmDurationField.Parts.total(hours: -1, minutes: 30, ceiling: day), 0)
        XCTAssertEqual(HelmDurationField.Parts.total(hours: 1, minutes: -30, ceiling: day), 0)
    }
}
