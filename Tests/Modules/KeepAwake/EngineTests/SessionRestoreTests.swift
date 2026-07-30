import XCTest
@testable import Module_KeepAwake_Engine

/// What a session that outlived its process is worth on the way back.
///
/// The decision is small and every branch of it is a judgement rather than
/// arithmetic, which is why it is a pure unit and not four `if`s inside
/// `activate()`.
final class SessionRestoreTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Nothing to restore

    func testNoSessionRestoresNothing() {
        XCTAssertEqual(SessionRestore.decide(manualOn: false, startDate: nil,
                                             endDate: nil, now: now),
                       .none)
    }

    /// The dates are the deadline of a session, not the session. A stored
    /// deadline with the session switched off is stale bookkeeping, and reviving
    /// it would keep the Mac awake because of something the person turned off.
    func testADeadlineWithoutASessionIsIgnored() {
        XCTAssertEqual(SessionRestore.decide(manualOn: false, startDate: now,
                                             endDate: now.addingTimeInterval(3600), now: now),
                       .none)
    }

    // MARK: - The session is over

    /// The one that matters most: the app was gone longer than the session had
    /// left. Two hours asked for, the process died at twenty minutes and came
    /// back three hours later — resuming would keep the Mac awake for a stretch
    /// nobody asked for, hours after they stopped watching.
    func testADeadlineThatPassedWhileTheAppWasGoneIsOver() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: now.addingTimeInterval(-7200),
                                             endDate: now.addingTimeInterval(-3600), now: now),
                       .none)
    }

    /// Exactly at the deadline is over, not one last instant of it.
    func testADeadlineExactlyNowIsOver() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: now.addingTimeInterval(-3600),
                                             endDate: now, now: now),
                       .none)
    }

    // MARK: - The session continues

    func testATimedSessionComesBackWithWhatIsLeftOfIt() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: now.addingTimeInterval(-600),
                                             endDate: now.addingTimeInterval(1800), now: now),
                       .remaining(1800))
    }

    /// `startSession(minutes: 0)` is a session with no deadline — the person
    /// asked for "until I say stop", and a relaunch is not them saying stop.
    func testAnIndefiniteSessionComesBackIndefinite() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: nil,
                                             endDate: nil, now: now),
                       .indefinite)
    }

    // MARK: - The clock is not to be trusted

    /// A session cannot come back longer than it ever was. If the system clock
    /// moves backwards — an NTP correction, a timezone change, a battery-dead
    /// Mac starting from an epoch — `endDate - now` exceeds the whole duration,
    /// and a two-hour session restored as a nine-hour one is the same defect as
    /// the one being fixed, wearing the opposite sign. `startDate` is stored for
    /// the countdown arc; it also bounds this.
    func testAClockThatMovedBackwardsCannotLengthenTheSession() {
        // A 30-minute session, but "now" is a day earlier than it started.
        let started = now.addingTimeInterval(86_400)
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: started,
                                             endDate: started.addingTimeInterval(1800),
                                             now: now),
                       .remaining(1800))
    }

    /// And without a start date there is nothing to bound it with, so the
    /// remaining time is taken at face value. Recorded rather than asserted as
    /// desirable: every path that writes an `endDate` writes a `startDate` beside
    /// it, so this combination only arises from a store somebody edited.
    func testWithoutAStartDateTheDeadlineIsTakenAtFaceValue() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: nil,
                                             endDate: now.addingTimeInterval(120), now: now),
                       .remaining(120))
    }
}
