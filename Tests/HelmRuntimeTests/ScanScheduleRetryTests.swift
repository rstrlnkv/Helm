import XCTest
@testable import HelmRuntime

/// The budget says two runs a day, and until now the second could never happen.
///
/// `lastScanAt` was written when a scan *started*, and `.notDue` refuses for
/// twenty-four hours after it — so any attempt, including one that came back
/// with nothing because the walk was cut short or the root was refused, spent
/// the whole day. The allowance whose stated purpose is "a second run if the
/// first was cut short" was unreachable by construction.
///
/// So the schedule is told two different facts: when a scan last **finished**,
/// and when one was last **attempted**. A finish holds the day; an attempt holds
/// only the retry gap.
final class ScanScheduleRetryTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func conditions(lastRun: Date? = nil, lastAttempt: Date? = nil,
                            runsToday: Int = 0) -> ScanSchedule.Conditions {
        .init(now: now, lastRun: lastRun, idleSeconds: 3600, onMains: true,
              runsToday: runsToday, isEnabled: true, lastAttempt: lastAttempt)
    }

    /// A scan that answered stands for the day, whatever the budget says.
    func testAFinishedScanHoldsTheWholeDay() {
        let finished = now.addingTimeInterval(-3600 * 5)
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastRun: finished,
                                                       lastAttempt: finished,
                                                       runsToday: 1)),
                       .notDue)
    }

    /// An attempt that answered nothing is not the day's scan — but it must not
    /// be retried a minute later either, or a folder that always refuses would
    /// be walked every tick until the budget is gone.
    func testAnAttemptThatAnsweredNothingIsRetriedAfterTheGapAndNotBefore() {
        let attempt = now.addingTimeInterval(-ScanSchedule.retryInterval / 2)
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastAttempt: attempt, runsToday: 1)),
                       .notDue)

        let older = now.addingTimeInterval(-ScanSchedule.retryInterval - 60)
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastAttempt: older, runsToday: 1)),
                       .run)
    }

    /// And the day's allowance is still the ceiling: a scan that fails twice
    /// does not go on failing all afternoon.
    func testTheBudgetStillStopsTheThirdAttempt() {
        let older = now.addingTimeInterval(-ScanSchedule.retryInterval - 60)
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastAttempt: older,
                                                       runsToday: ScanSchedule.runsPerDay)),
                       .spent)
    }

    /// A machine that has never scanned runs, with neither fact recorded.
    func testAFirstEverScanRuns() {
        XCTAssertEqual(ScanSchedule.verdict(conditions()), .run)
    }

    /// The clock check covers both facts. An attempt stamped in the future is
    /// the same restored backup as a run stamped in the future, and reading it
    /// as "never attempted" would let a scan start every minute.
    func testAnAttemptInTheFutureIsClockSkew() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastAttempt: now.addingTimeInterval(3600))),
                       .clockSkew)
    }
}
