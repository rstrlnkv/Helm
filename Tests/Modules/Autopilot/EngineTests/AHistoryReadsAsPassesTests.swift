import XCTest
@testable import Module_Autopilot_Engine

/// Five hundred rows is not a thing anybody can act on. A sweep is: twelve
/// files arrived in Downloads at 14:22 and one gesture puts them back.
///
/// So the page reads the history in passes, and everything the header says has
/// to come out of the records themselves — a header that says "Downloads" over
/// rows from two folders is a claim about somebody's Mac that nothing checked.
final class AHistoryReadsAsPassesTests: XCTestCase {

    private func at(_ hour: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(hour) * 3600) }

    private func record(_ file: String, run: String?, at hour: Int,
                        folder: String = "/Users/x/Downloads",
                        kind: ActionRecord.Kind = .moved,
                        identified: Bool = true,
                        undoneAt: Date? = nil) -> ActionRecord {
        ActionRecord(at: at(hour), rule: "Sort", file: file, kind: kind, detail: "Invoices",
                     path: folder + "/" + file,
                     destination: "/Users/x/Documents/Invoices/" + file,
                     run: run, ruleID: "r",
                     device: identified ? 1 : nil, inode: identified ? 7 : nil,
                     undoneAt: undoneAt)
    }

    func testTheRecordsOfOnePassAreOneGroupNewestFirst() {
        let history = [record("c.pdf", run: "two", at: 5),
                       record("b.pdf", run: "one", at: 2),
                       record("a.pdf", run: "one", at: 1)]

        let runs = ActionHistory.runs(of: history, now: at(6))

        XCTAssertEqual(runs.map(\.id), ["two", "one"])
        XCTAssertEqual(runs.last?.records.map(\.file), ["b.pdf", "a.pdf"])
    }

    /// The header's time is the pass's, and a pass happened at one moment as
    /// far as anybody reading is concerned: the newest of its records.
    func testAPassIsStampedWithItsNewestAction() {
        let runs = ActionHistory.runs(of: [record("b.pdf", run: "one", at: 4),
                                           record("a.pdf", run: "one", at: 1)],
                                      now: at(6))
        XCTAssertEqual(runs.first?.at, at(4))
    }

    /// The folder is only named when there is one to name. A watched folder
    /// with subfolders makes a pass that touched three of them, and "Downloads"
    /// over rows from `2025` and `2026` would be a header inventing a fact.
    func testTheFolderIsNamedOnlyWhenThePassCameFromOne() {
        let one = ActionHistory.runs(of: [record("a.pdf", run: "one", at: 1),
                                          record("b.pdf", run: "one", at: 2)],
                                     now: at(6))
        XCTAssertEqual(one.first?.folder, "Downloads")

        let two = ActionHistory.runs(of: [record("a.pdf", run: "one", at: 1,
                                                 folder: "/Users/x/Downloads/2025"),
                                          record("b.pdf", run: "one", at: 2,
                                                 folder: "/Users/x/Downloads/2026")],
                                     now: at(6))
        XCTAssertNil(two.first?.folder)
    }

    /// A history written before this build has no passes in it. Each record
    /// stands alone rather than collapsing into one enormous group that a
    /// single press would try to put back.
    func testRecordsWithNoPassStandAlone() {
        let runs = ActionHistory.runs(of: [record("a.pdf", run: nil, at: 1),
                                           record("b.pdf", run: nil, at: 2)],
                                      now: at(6))
        XCTAssertEqual(runs.count, 2)
        XCTAssertEqual(runs.flatMap { $0.records.map(\.file) }, ["b.pdf", "a.pdf"])
        XCTAssertEqual(runs.map(\.canBePutBack), [false, false],
                       "a record with no pass was offered a whole-pass return")
    }

    /// What the button on the header is allowed to say. A pass of twelve rows
    /// where nine can be put back offers nine, not twelve — the count on a
    /// button is a promise.
    func testAPassOffersOnlyTheRowsThatCouldGoBack() {
        let history = [record("a.pdf", run: "one", at: 1),
                       record("b.pdf", run: "one", at: 2, kind: .refused, identified: false),
                       record("c.pdf", run: "one", at: 3, undoneAt: at(4))]

        let run = ActionHistory.runs(of: history, now: at(6)).first

        XCTAssertEqual(run?.records.count, 3, "the rows that cannot go back stopped being shown")
        XCTAssertEqual(run?.undoable.map(\.file), ["a.pdf"])
        XCTAssertEqual(run?.canBePutBack, true)
    }

    func testAPassWhereNothingCanGoBackOffersNothing() {
        let run = ActionHistory.runs(of: [record("a.pdf", run: "one", at: 1, undoneAt: at(2))],
                                     now: at(6)).first
        XCTAssertEqual(run?.undoable, [])
        XCTAssertEqual(run?.canBePutBack, false)
    }

    /// The window applies here as everywhere else it is read: a pass whose
    /// records fell out of the last thirty days is not a group of nothing.
    func testAPassOlderThanTheWindowIsNotAGroup() {
        let runs = ActionHistory.runs(of: [record("old.pdf", run: "one", at: 1)],
                                      now: at(24 * 40))
        XCTAssertEqual(runs, [])
    }
}
