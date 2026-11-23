import XCTest
@testable import HelmRuntime

/// The clock and the conditions builder both schedule classes below inherit.
/// It holds no test of its own.
class ScanScheduleRig: XCTestCase {

    fileprivate let noon = Date(timeIntervalSince1970: 1_785_672_000)

    fileprivate func conditions(idle: TimeInterval = 600,
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
}

/// A background scan reads every file in its scope. It runs when that costs the
/// person nothing, and the definition of "nothing" is this file.
final class ScanScheduleTests: ScanScheduleRig {
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
}
