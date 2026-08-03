import XCTest
@testable import HelmRuntime

/// A background scan reads every file in its scope. It runs when that costs the
/// person nothing, and the definition of "nothing" is this file.
final class ScanScheduleTests: XCTestCase {

    private let noon = Date(timeIntervalSince1970: 1_785_672_000)
    private let interval: TimeInterval = 24 * 3600

    private func conditions(idle: TimeInterval = 600,
                            onMains: Bool = true,
                            ranToday: Int = 0,
                            lastRun: Date? = nil,
                            enabled: Bool = true,
                            onConsole: Bool = true,
                            screenLocked: Bool = false) -> ScanSchedule.Conditions {
        ScanSchedule.Conditions(now: noon, lastRun: lastRun, idleSeconds: idle,
                                onMains: onMains, runsToday: ranToday,
                                isEnabled: enabled, onConsole: onConsole,
                                screenLocked: screenLocked)
    }

    func testRunsWhenEverythingIsFavourable() {
        XCTAssertEqual(ScanSchedule.verdict(conditions()), .run)
    }

    /// The switch in Settings is the person's answer and outranks every other
    /// condition, including a scan that is overdue.
    func testASwitchedOffScanNeverRuns() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(enabled: false)), .off)
    }

    /// Two minutes of stillness is a person reading, not a person away. Five is
    /// the threshold, and below it the scan waits rather than competing with
    /// whatever they are doing.
    func testWaitsWhileSomebodyIsUsingTheMac() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(idle: 120)), .busy)
        XCTAssertEqual(ScanSchedule.verdict(conditions(idle: 299)), .busy)
        XCTAssertEqual(ScanSchedule.verdict(conditions(idle: 300)), .run)
    }

    /// Reading every file in scope off a battery is the opposite of what this
    /// app is for.
    func testWaitsForMains() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(onMains: false)), .onBattery)
    }

    /// Once a day. A scan that already ran is not due again because the app
    /// relaunched — which is what a naive "run at launch" would do to somebody
    /// who opens and quits Helm five times an afternoon.
    func testOncePerDay() {
        let fourHoursAgo = noon.addingTimeInterval(-4 * 3600)
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastRun: fourHoursAgo)), .notDue)
        let yesterday = noon.addingTimeInterval(-25 * 3600)
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastRun: yesterday)), .run)
    }

    /// Exactly a day is due. `>=` against `>` is one character and a day of
    /// difference.
    func testExactlyOneDayIsDue() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastRun: noon.addingTimeInterval(-interval))),
                       .run)
    }

    /// A first run has no last run, and must not be blocked by its absence.
    func testAFirstRunIsDue() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(lastRun: nil)), .run)
    }

    /// The budget is the backstop for a clock that jumped — a timezone change, a
    /// restored backup, a machine whose date was wrong.
    func testTheDailyBudgetStopsARunawayClock() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(ranToday: 2)), .spent)
    }

    /// A restored backup leaves `lastRun` ahead of `now`. Without a name for it,
    /// `timeIntervalSince` is negative, negative is less than a day, and the
    /// ordinary rule refuses the scan every minute for thirty days while the
    /// Settings row reports «не пора» — which is not what is wrong.
    func testAFutureLastRunIsNamedRatherThanSilentlyRefused() {
        let restored = conditions(lastRun: noon.addingTimeInterval(30 * 86400))
        XCTAssertEqual(ScanSchedule.verdict(restored), .clockSkew)
    }

    /// Fast user switching and a locked screen both stop this session receiving
    /// events, so `idleSeconds` grows without bound and looks like an empty
    /// desk. Reading one person's home folder while another is at the keyboard
    /// is the outcome this refuses.
    func testAnotherUserAtTheConsoleStopsTheScan() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(idle: 9999, onConsole: false)),
                       .notAtTheConsole)
    }

    func testALockedScreenStopsTheScan() {
        XCTAssertEqual(ScanSchedule.verdict(conditions(idle: 9999, screenLocked: true)),
                       .notAtTheConsole)
    }

    /// The order is the decision, and it is what these two pin. `.notDue`
    /// outranks both machine-state refusals, so moving the mains check above the
    /// day check fails here.
    func testNotDueOutranksTheMachineState() {
        let fourHoursAgo = noon.addingTimeInterval(-4 * 3600)
        XCTAssertEqual(ScanSchedule.verdict(conditions(onMains: false, lastRun: fourHoursAgo)),
                       .notDue)
        XCTAssertEqual(ScanSchedule.verdict(conditions(idle: 0, lastRun: fourHoursAgo)),
                       .notDue)
    }

    /// Off outranks everything, so "you switched this off" is never reported as
    /// "your Mac is busy".
    func testOffOutranksEveryOtherRefusal() {
        let hostile = ScanSchedule.Conditions(now: noon, lastRun: nil, idleSeconds: 0,
                                              onMains: false, runsToday: 9,
                                              isEnabled: false, onConsole: false,
                                              screenLocked: true)
        XCTAssertEqual(ScanSchedule.verdict(hostile), .off)
    }

    /// The budget outranks the clock.
    ///
    /// A `lastRun` in the future is a real state — a restored backup — and a
    /// scan that has already run twice today must be refused for the budget
    /// rather than reported as a clock problem. This is also the assertion that
    /// makes the ordering mutation-checkable: with `lastRun: nil` the day rule
    /// never fires, so moving the budget below it would break nothing and the
    /// test would be guarding an order it cannot see.
    func testTheBudgetOutranksTheClock() {
        let future = noon.addingTimeInterval(3600)
        XCTAssertEqual(ScanSchedule.verdict(conditions(ranToday: 2, lastRun: future)), .spent)
    }
}
