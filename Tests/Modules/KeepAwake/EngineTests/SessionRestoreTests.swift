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

    /// Without a start date there is nothing *relative* to bound it with, and a
    /// deadline inside what this module can start is taken at face value. Every
    /// path that writes an `endDate` writes a `startDate` beside it, so this
    /// combination only arises from a store somebody edited — which is why the
    /// absolute bound below is the one that matters here.
    func testWithoutAStartDateAReachableDeadlineIsTakenAtFaceValue() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: nil,
                                             endDate: now.addingTimeInterval(120), now: now),
                       .remaining(120))
    }

    // MARK: - A deadline no session could have produced

    /// The bound above is **relative**, and it was the only one: a stored
    /// duration that is itself absurd is bounded by itself and comes back
    /// whole. Both of these reach `Int(left / 60)` in
    /// `KeepAwakeEngine.restoreSession`, which **traps** — "Double value cannot
    /// be converted to Int because the result would be greater than Int.max" —
    /// so the app terminates on launch, before anything is drawn, with no way
    /// back in to switch the session off. `<real>1e300</real>` is a legal plist
    /// and `UserDefaults` hands it straight back as a `Double`.
    ///
    /// Refused rather than clamped: nothing this module can start produces a
    /// deadline out here, so the value is not a long session, it is not a
    /// session. Clamping it to the ceiling would hold the Mac awake for a day
    /// on the strength of a number nobody wrote.
    func testADeadlineLongerThanAnySessionCouldBeIsRefused() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: nil,
                                             endDate: Date(timeIntervalSinceReferenceDate: 1e300),
                                             now: now),
                       .none)
    }

    /// And a start date does not rescue it. `min(left, endDate - startDate)` is
    /// a bound *by the stored duration*, so when that duration is the absurd
    /// number the bound is the absurd number — the missing condition was an
    /// absolute one, on both branches rather than on the second.
    func testAStartDateDoesNotRescueADeadlineThatIsItselfAbsurd() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: now.addingTimeInterval(-60),
                                             endDate: Date(timeIntervalSinceReferenceDate: 1e300),
                                             now: now),
                       .none)
    }

    /// `<real>inf</real>` reaches the same conversion. A date is not a number
    /// the module can subtract its way out of.
    func testANonFiniteDeadlineIsRefused() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: nil,
                                             endDate: Date(timeIntervalSinceReferenceDate: .infinity),
                                             now: now),
                       .none)
    }

    /// The same trap entered through the *other* stored field. Every test above
    /// moves the deadline; the bound is `min(left, endDate - startDate)`, so a
    /// start date **after** the end date makes that subtraction negative and the
    /// ceiling above waves it through — `isFinite` is true of -1e300 and it is
    /// certainly under a day. It then reaches the same `Int(left / 60)` in
    /// `KeepAwakeEngine.restoreSession` and traps at the other end: "the result
    /// would be less than Int.min". `<real>1e300</real>` in `sessionStartedAt`
    /// is as legal a plist as it is in `sessionEndsAt`.
    func testAStartDateAfterTheDeadlineIsRefused() {
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: Date(timeIntervalSinceReferenceDate: 1e300),
                                             endDate: now.addingTimeInterval(1800),
                                             now: now),
                       .none)
    }

    /// And the modest version, which does not trap and is worse for it: a start
    /// a minute past the deadline restores `.remaining(-60)`, so the module
    /// holds the IOKit assertion for a session that ended before it began and
    /// every surface draws 0:00 over it. A negative duration is not a session.
    func testASessionThatEndedBeforeItBeganIsRefused() {
        let ends = now.addingTimeInterval(1800)
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: ends.addingTimeInterval(60),
                                             endDate: ends, now: now),
                       .none)
    }

    /// Nor is a session of no length one. The two dates equal is the boundary
    /// between the refusal above and the control below, and it belongs to the
    /// refusal: there is nothing left to keep the Mac awake for.
    func testASessionOfNoLengthIsRefused() {
        let ends = now.addingTimeInterval(1800)
        XCTAssertEqual(SessionRestore.decide(manualOn: true, startDate: ends,
                                             endDate: ends, now: now),
                       .none)
    }

    /// The control, so the refusal above is a bound and not a blanket: the
    /// longest session anything in this module can start still comes back
    /// whole. `KeepAwakeSettings` caps both of its durations at a day, and the
    /// panel tile's own entry caps below that.
    ///
    /// The day is spelled out here rather than read from `TimerPolicy`: a test
    /// that asks the subject what its own bound is passes whatever the bound
    /// becomes.
    func testTheLongestSessionThisModuleCanStartStillComesBack() {
        let aDay: TimeInterval = 24 * 60 * 60
        XCTAssertEqual(SessionRestore.decide(manualOn: true,
                                             startDate: now,
                                             endDate: now.addingTimeInterval(aDay), now: now),
                       .remaining(aDay))
    }
}
