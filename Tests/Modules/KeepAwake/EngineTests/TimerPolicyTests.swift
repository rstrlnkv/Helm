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

    // MARK: - The panel tile's "+15"

    /// The button reads the countdown on the screen and asks for a session that
    /// long plus fifteen minutes, so a part-minute counts as a whole one: with
    /// 61 seconds showing, "+15" must not end up shorter than the countdown it
    /// was pressed on.
    func testFifteenMinutesIsAddedToWhatIsLeftRoundedUp() {
        XCTAssertEqual(TimerPolicy.extendedMinutes(remaining: 0, adding: 15), 15)
        XCTAssertEqual(TimerPolicy.extendedMinutes(remaining: 60, adding: 15), 16)
        XCTAssertEqual(TimerPolicy.extendedMinutes(remaining: 61, adding: 15), 17)
        XCTAssertEqual(TimerPolicy.extendedMinutes(remaining: 30 * 60, adding: 15), 45)
    }

    /// The countdown is drawn from an `endDate` the engine restored from the
    /// store, so this arithmetic sits on a `Double` that came off disk. It was
    /// `Int(ceil(remaining / 60)) + 15` in the tile, and `Int(_:)` of a `Double`
    /// past `Int.max` **traps**: the app terminating when somebody presses the
    /// button on a countdown they can see.
    ///
    /// A remaining time no session could have is not a session to extend, so
    /// the button asks for its own fifteen minutes — the answer that keeps the
    /// Mac awake for the shortest time, and one the person can see and change.
    func testARemainingTimeNoSessionCouldHaveIsNotExtended() {
        for absurd in [1e300, .infinity, -Double.infinity, Double.nan] {
            XCTAssertEqual(TimerPolicy.extendedMinutes(remaining: absurd, adding: 15), 15,
                           "\(absurd) is not a countdown this module could have drawn")
        }
    }

    /// And the result cannot exceed what the module can start either: the
    /// payload goes to `startSession`, which turns minutes into seconds with a
    /// multiply that traps on `Int` overflow.
    func testTheExtendedSessionStopsAtTheLongestThisModuleCanStart() {
        let aDay = 24 * 60
        XCTAssertEqual(TimerPolicy.extendedMinutes(remaining: TimeInterval(aDay * 60), adding: 15),
                       aDay)
    }
}
