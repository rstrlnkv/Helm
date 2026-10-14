import XCTest
@testable import HelmRuntime

/// The arithmetic a background scan runs on, out of `HelmApp` where nothing
/// could test it.
///
/// Every case here was unreachable while these lines lived in
/// `ScanCoordinator`, and four defects found on 2026-08-03 could only be argued
/// about. Not because `HelmApp` cannot be tested — `HelmAppTests` exists — but
/// because the clock and the transport call were in the way of the arithmetic.
final class ScanRunnerTests: XCTestCase {

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: - Idleness

    /// Nothing to compare against: the counter is the answer.
    func testTheFirstReadingIsTheCounter() {
        let idle = ScanRunner.advance(nil, systemIdle: 42, lastOwnNudge: nil, now: t0)
        XCTAssertEqual(idle.personSeconds, 42)
    }

    /// Nobody touched anything: the counter climbs and is believed.
    func testAClimbingCounterIsFollowed() {
        var idle = ScanRunner.advance(nil, systemIdle: 60, lastOwnNudge: nil, now: t0)
        idle = ScanRunner.advance(idle, systemIdle: 120, lastOwnNudge: nil,
                                  now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 120)
    }

    /// **The defect this unit exists for.** Keep Awake jiggles the pointer, the
    /// counter drops to nothing, and the person has not moved. The old code
    /// returned `sinceNudge + system` — and the branch fired exactly when those
    /// two were equal, so it answered roughly **double**: with the nudge at its
    /// default five minutes, a scan whose threshold is 300 s could start after
    /// 150 seconds of real stillness.
    func testOurOwnNudgeNeitherResetsNorDoublesTheAnswer() {
        // Ten minutes of stillness, then our nudge, then a minute more.
        var idle = ScanRunner.advance(nil, systemIdle: 600, lastOwnNudge: nil, now: t0)
        let nudgedAt = t0.addingTimeInterval(30)
        let now = t0.addingTimeInterval(90)
        idle = ScanRunner.advance(idle, systemIdle: 60, lastOwnNudge: nudgedAt, now: now)
        // 600 seconds already still, plus the 90 that passed. Not 60 (the
        // counter, which measures our own event) and not 120 (the doubling).
        XCTAssertEqual(idle.personSeconds, 690, accuracy: 0.001)
    }

    /// An hour of stillness with the nudge firing every five minutes reads as an
    /// hour — not as five minutes, and not as two hours.
    func testAnHourOfStillnessUnderARepeatingNudgeReadsAsAnHour() {
        var idle = ScanRunner.advance(nil, systemIdle: 0, lastOwnNudge: nil, now: t0)
        var now = t0
        for minute in 1...60 {
            now = t0.addingTimeInterval(TimeInterval(minute) * 60)
            // The nudge lands every fifth minute and takes the counter down.
            let nudged = minute % 5 == 0
            let nudgeAt = nudged ? now : t0.addingTimeInterval(TimeInterval((minute / 5) * 5 * 60))
            let system: TimeInterval = nudged ? 0 : TimeInterval(minute % 5) * 60
            idle = ScanRunner.advance(idle, systemIdle: system, lastOwnNudge: nudgeAt, now: now)
        }
        XCTAssertEqual(idle.personSeconds, 3600, accuracy: 1)
    }

    /// A hand on the trackpad is not our nudge, and the estimate must collapse
    /// to what the counter says — otherwise a scan starts while somebody works.
    func testAPersonTouchingTheMacResetsTheEstimate() {
        var idle = ScanRunner.advance(nil, systemIdle: 900, lastOwnNudge: nil, now: t0)
        // Our last nudge was long ago, so this reset is not ours.
        idle = ScanRunner.advance(idle, systemIdle: 3, lastOwnNudge: t0.addingTimeInterval(-600),
                                  now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 3)
    }

    /// Even mid-accumulation. The estimate is a floor built on the counter, and
    /// the counter overtaking it is the counter being right.
    func testTheAnswerIsNeverLessThanTheCounter() {
        var idle = ScanRunner.advance(nil, systemIdle: 10, lastOwnNudge: nil, now: t0)
        idle = ScanRunner.advance(idle, systemIdle: 5000, lastOwnNudge: nil,
                                  now: t0.addingTimeInterval(30))
        XCTAssertEqual(idle.personSeconds, 5000)
    }

    /// A clock corrected backwards must not hand out idleness nobody earned.
    func testAClockMovingBackwardsDoesNotInflateIdleness() {
        var idle = ScanRunner.advance(nil, systemIdle: 300, lastOwnNudge: nil, now: t0)
        idle = ScanRunner.advance(idle, systemIdle: 30, lastOwnNudge: t0,
                                  now: t0.addingTimeInterval(-3600))
        XCTAssertEqual(idle.personSeconds, 30)
    }

    // MARK: - A counter that did not climb

    private func verdict(idleSeconds: TimeInterval) -> ScanSchedule.Verdict {
        ScanSchedule.verdict(ScanSchedule.Conditions(
            now: t0.addingTimeInterval(86_400 * 3), lastRun: nil,
            idleSeconds: idleSeconds, onMains: true, runsToday: 0, isEnabled: true))
    }

    /// The counter read 10 s a minute ago, after our nudge; the person touched
    /// the Mac five seconds into the minute and the counter now reads 55. That
    /// is above the 10 it read before, so it is not "lower than the last
    /// reading", yet it failed to climb by the 60 s that passed. Our last nudge
    /// was ten seconds before the previous reading, nowhere near the moment the
    /// counter was last zero. The person is at the keyboard: 55, and no scan.
    func testACounterThatFailedToClimbByTheElapsedTimeIsAPersonsHand() {
        let previous = ScanRunner.Idle(personSeconds: 1200, systemSeconds: 10, readAt: t0)
        let idle = ScanRunner.advance(previous, systemIdle: 55,
                                      lastOwnNudge: t0.addingTimeInterval(-10),
                                      now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 55, accuracy: 0.001)
        XCTAssertEqual(verdict(idleSeconds: idle.personSeconds), .busy)
    }

    /// The same shape with no nudge of ours ever recorded.
    func testACounterThatFailedToClimbWithNoNudgeOnRecordIsAPersonsHand() {
        let previous = ScanRunner.Idle(personSeconds: 1200, systemSeconds: 10, readAt: t0)
        let idle = ScanRunner.advance(previous, systemIdle: 55, lastOwnNudge: nil,
                                      now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 55, accuracy: 0.001)
    }

    /// Our own nudge inside the tick: the counter read 10 s, the nudge landed
    /// 30 s later and zeroed it, and 30 s after that it reads 30. It did not
    /// climb by the 60 s that passed, and the moment it was last zero is our
    /// nudge. The person has not moved, so the estimate keeps accumulating —
    /// or no scan ever runs for anybody with Keep Awake on.
    func testANudgeOfOursInsideTheTickKeepsTheEstimateAccumulating() {
        let previous = ScanRunner.Idle(personSeconds: 1200, systemSeconds: 10, readAt: t0)
        let idle = ScanRunner.advance(previous, systemIdle: 30,
                                      lastOwnNudge: t0.addingTimeInterval(30),
                                      now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 1260, accuracy: 0.001)
        XCTAssertEqual(verdict(idleSeconds: idle.personSeconds), .run)
    }

    /// The nudge inside the tick, the counter above its previous reading but
    /// below the elapsed time, a nudge recorded two seconds off the moment the
    /// counter was last zero: still ours, within the tolerance.
    func testANudgeTwoSecondsOffTheCounterZeroIsStillOurs() {
        let previous = ScanRunner.Idle(personSeconds: 1200, systemSeconds: 10, readAt: t0)
        let idle = ScanRunner.advance(previous, systemIdle: 40,
                                      lastOwnNudge: t0.addingTimeInterval(18),
                                      now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 1260, accuracy: 0.001)
    }

    /// A counter a second short of the elapsed time is the counter and the
    /// clock being read at different instants, not a hand: the tolerance the
    /// nudge comparison already allows applies to the climb as well.
    func testACounterASecondShortOfTheElapsedTimeIsStillClimbing() {
        let previous = ScanRunner.Idle(personSeconds: 400, systemSeconds: 100, readAt: t0)
        let idle = ScanRunner.advance(previous, systemIdle: 159, lastOwnNudge: nil,
                                      now: t0.addingTimeInterval(60))
        XCTAssertEqual(idle.personSeconds, 460, accuracy: 0.001)
    }

    // MARK: - The day

    func testAMachineThatHasNeverCountedRollsOver() {
        XCTAssertTrue(ScanRunner.dayRolledOver(storedDay: nil, now: t0))
    }

    func testTheSameDayDoesNotRollOver() {
        let calendar = Calendar.current
        let morning = calendar.startOfDay(for: t0)
        XCTAssertFalse(ScanRunner.dayRolledOver(storedDay: morning,
                                                now: morning.addingTimeInterval(3600 * 13)))
    }

    /// Compared against the calendar, never against multiples of 86 400: a day
    /// with a clock change is not 86 400 seconds long.
    func testTheNextDayRollsOver() {
        let calendar = Calendar.current
        let morning = calendar.startOfDay(for: t0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: morning)!
        XCTAssertTrue(ScanRunner.dayRolledOver(storedDay: morning, now: tomorrow))
    }
}
