import XCTest
@testable import Module_Autopilot_Engine

/// The history has one job: answer "what happened to my file" a week later.
///
/// `ActionRecord.of` already knows that an outcome which repeats on every sweep
/// must not be written down — `.alreadyDone` returns nil, and the reason given
/// is that "recording that would bury the day's real work under it". A refusal
/// and a failure repeat on exactly the same schedule and for exactly the same
/// reason: nothing about the file changed, so the next sweep decides the same
/// thing. Neither is filtered, and 500 rows is not many hours of that.
final class ActionHistoryFloodTests: XCTestCase {

    private func hour(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 3_600) }

    /// A file the sweep can never act on. Reachable several ways, none of them
    /// exotic: a symlink in `~/Downloads` pointing at `/Applications`
    /// (`WatchScope` resolves it and refuses), a move rule whose destination is
    /// outside the home directory, a rename pattern that yields a name the
    /// filesystem must not be asked to take. The rule matches, the runner
    /// refuses, nothing is stamped, and the next hour it all happens again.
    private func refusal(atHour n: Int) -> ActionRecord {
        ActionRecord(at: hour(n), rule: "Sort downloads", file: "shortcut",
                     kind: .refused, detail: "outOfScope")
    }

    /// Thirty days of hourly sweeps: one file refused every time, and on the
    /// first morning one real move — the one the person comes back to look for.
    ///
    /// Written the way `AutopilotEngine.remember` writes it: oldest first, one
    /// `recording` call each.
    private func aMonthOfSweeps(now: Date) -> [ActionRecord] {
        let move = ActionRecord(at: hour(9), rule: "Invoices", file: "march.pdf",
                                kind: .moved, detail: "Invoices")
        var history: [ActionRecord] = []
        for sweep in 0..<(30 * 24) {
            if sweep == 9 { history = ActionHistory.recording(move, into: history, now: now) }
            history = ActionHistory.recording(refusal(atHour: sweep), into: history, now: now)
        }
        return history
    }

    func testARefusalThatRepeatsEveryHourDoesNotEvictTheWork() {
        let now = hour(30 * 24)
        let history = aMonthOfSweeps(now: now)

        XCTAssertTrue(history.contains { $0.file == "march.pdf" },
                      "the page promises thirty days; after \(history.count) rows of one "
                      + "file refusing, the only thing Autopilot actually did is gone")
    }

    /// The same defect where the page states it first: the headline over the
    /// list. One file was moved inside the window, so a summary of that window
    /// that says nothing was moved is wrong about the month.
    func testTheSummaryStillKnowsAFileWasMoved() {
        let now = hour(30 * 24)
        let summary = ActionHistory.summary(of: aMonthOfSweeps(now: now), now: now)

        XCTAssertEqual(summary.moved, 1,
                       "march.pdf was moved nine hours into the window and is still "
                       + "inside it; the summary counts \(summary.refused) refusals and "
                       + "\(summary.moved) moves")
    }
}
