import XCTest
@testable import Module_Autopilot_Engine

/// The history has one job: answer "what happened to my file" a week later.
///
/// An outcome that repeats on every sweep must not bury the day's real work:
/// `ActionRecord.of` returns nil for `.alreadyDone`. A refusal and a failure
/// repeat on the same schedule for the same reason (nothing about the file
/// changed, so the next sweep decides the same thing), and 500 rows of them
/// would be gone in a few weeks of hourly sweeps.
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

    /// Where the page states it first: the headline over the list. One file
    /// was moved inside the window, so a summary of that window
    /// that says nothing was moved is wrong about the month.
    func testTheSummaryStillKnowsAFileWasMoved() {
        let now = hour(30 * 24)
        let summary = ActionHistory.summary(of: aMonthOfSweeps(now: now), now: now)

        XCTAssertEqual(summary.moved, 1,
                       "march.pdf was moved nine hours into the window and is still "
                       + "inside it; the summary counts \(summary.refused) refusals and "
                       + "\(summary.moved) moves")
    }

    /// The cap itself: distinct work, more of it than the limit, inside the
    /// window. Refusals collapse, so only real actions reach it.
    func testTheHistoryHoldsNoMoreThanTheLimit() {
        let now = hour(30 * 24)
        var history: [ActionRecord] = []
        for n in 0..<(ActionHistory.limit + 5) {
            let move = ActionRecord(at: hour(n), rule: "Invoices", file: "file\(n).pdf",
                                    kind: .moved, detail: "Invoices")
            history = ActionHistory.recording(move, into: history, now: now)
        }

        XCTAssertEqual(history.count, ActionHistory.limit)
        XCTAssertEqual(history.first?.file, "file\(ActionHistory.limit + 4).pdf",
                       "the newest leads")
    }
}
