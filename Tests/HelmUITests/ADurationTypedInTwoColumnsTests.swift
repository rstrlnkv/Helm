import XCTest
@testable import HelmUI

/// The arithmetic behind the Clock-shaped duration field.
///
/// It looks like nothing — divide by sixty, multiply by sixty — and it is the
/// part that can be wrong in a way nobody sees. A person types `90` into the
/// minutes column meaning an hour and a half; a plist hands over a number no
/// session could have produced; somebody pastes into the hours box. Every one
/// of those has to come out as a duration this module can actually start.
final class ADurationTypedInTwoColumnsTests: XCTestCase {

    private let day = 24 * 60

    // MARK: - Splitting

    func testAnOrdinaryDurationSplitsIntoHoursAndMinutes() {
        let parts = HelmDurationField.Parts.split(95, ceiling: day)
        XCTAssertEqual(parts.hours, 1)
        XCTAssertEqual(parts.minutes, 35)
    }

    func testAWholeHourLeavesNoMinutes() {
        let parts = HelmDurationField.Parts.split(120, ceiling: day)
        XCTAssertEqual(parts.hours, 2)
        XCTAssertEqual(parts.minutes, 0)
    }

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

    func testTheTwoColumnsAddUp() {
        XCTAssertEqual(HelmDurationField.Parts.total(hours: 1, minutes: 35, ceiling: day), 95)
    }

    /// **Ninety in the minutes box is not an error.** Somebody who types it has
    /// said an hour and a half, and clamping the column to 59 would be the
    /// field correcting a person who was not wrong.
    func testMinutesPastSixtyCarryRatherThanBeingRefused() {
        XCTAssertEqual(HelmDurationField.Parts.total(hours: 0, minutes: 90, ceiling: day), 90,
                       "the field refused a number that means an hour and a half")
        let parts = HelmDurationField.Parts.split(90, ceiling: day)
        XCTAssertEqual(parts.hours, 1, "…and it is drawn back as 1:30 on the next redraw")
        XCTAssertEqual(parts.minutes, 30)
    }

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

    /// Split and join are each other's inverse for every duration the field can
    /// hold — the property that makes the two columns a *view* of one number
    /// rather than two numbers that have to be kept in step.
    func testSplittingAndJoiningIsTheSameNumberBack() {
        for minutes in stride(from: 0, through: day, by: 7) {
            let parts = HelmDurationField.Parts.split(minutes, ceiling: day)
            XCTAssertEqual(HelmDurationField.Parts.total(hours: parts.hours,
                                                         minutes: parts.minutes,
                                                         ceiling: day),
                           minutes, "round trip lost \(minutes)")
        }
    }
}
