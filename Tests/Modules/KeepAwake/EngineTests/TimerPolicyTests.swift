import XCTest
@testable import Module_KeepAwake_Engine

/// Guards: aff8a787 (extendedMinutes trapped on a stored deadline off the ceiling).
final class TimerPolicyTests: XCTestCase {
    /// (auto condition, suppressed, timer ends automation, expected, why). The two
    /// rows with a running rule's app and nothing suppressed are each other's control.
    func testOnExpiry() {
        let rows: [(Bool, Bool, Bool, TimerPolicy.Action, String)] = [
            (false, false, false, .deactivate, "no automatic condition: the session ends because the timer ended"),
            (true, false, false, .continueAsAuto, "the timer ran out, a rule's app still runs: without the setting it carries on"),
            (true, true, false, .deactivate, "suppressed rule: nothing to carry on as"),
            (true, false, true, .deactivate, "the person asked for the timer to be the end of it: the control of the row above"),
            (false, false, true, .deactivate, "no automatic condition: nothing for the setting to change"),
            (true, true, true, .deactivate, "already suppressed is already the answer the setting produces")
        ]
        for (auto, suppressed, ends, expected, why) in rows {
            XCTAssertEqual(TimerPolicy.onExpiry(hasAutoCondition: auto, suppressed: suppressed,
                                                timerEndsAutomation: ends), expected, why)
        }
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
