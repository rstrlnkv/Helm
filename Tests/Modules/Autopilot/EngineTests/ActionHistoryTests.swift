import XCTest
@testable import Module_Autopilot_Engine

/// Autopilot is the one module that acts while nobody is watching. Without a
/// record, a file that moved is indistinguishable from a file that was lost,
/// and the only honest thing anyone could do was distrust the whole module.
final class ActionHistoryTests: XCTestCase {

    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
    private func entry(_ file: String, at n: Int, _ what: ActionRecord.Kind = .moved,
                       detail: String = "Documents") -> ActionRecord {
        ActionRecord(at: day(n), rule: "Invoices", file: file, kind: what, detail: detail)
    }

    // MARK: - Keeping

    func testTheNewestActionComesFirst() {
        let history = ActionHistory.recording(entry("c.pdf", at: 30),
                                              into: [entry("a.pdf", at: 10),
                                                     entry("b.pdf", at: 20)],
                                              now: day(30))
        XCTAssertEqual(history.map(\.file), ["c.pdf", "b.pdf", "a.pdf"])
    }

    func testAnActionOlderThanThirtyDaysIsDropped() {
        let old = entry("ancient.pdf", at: 0)
        let history = ActionHistory.recording(entry("new.pdf", at: 40), into: [old], now: day(40))
        XCTAssertEqual(history.map(\.file), ["new.pdf"])
    }

    /// The boundary is a boundary, not a guess: an action from exactly thirty
    /// days ago is still inside the window the page promises.
    func testExactlyThirtyDaysOldIsStillShown() {
        let edge = entry("edge.pdf", at: 10)
        let history = ActionHistory.recording(entry("new.pdf", at: 40), into: [edge], now: day(40))
        XCTAssertEqual(history.map(\.file), ["new.pdf", "edge.pdf"])
    }

    /// A busy Downloads folder can act hundreds of times a day, and this lives
    /// in the same store as the rules: unbounded, it would eventually be the
    /// reason the rules fail to save.
    func testTheHistoryStopsGrowing() {
        let many = (0..<ActionHistory.limit + 50).map { entry("f\($0).pdf", at: 30) }
        let history = ActionHistory.recording(entry("newest.pdf", at: 30), into: many, now: day(30))
        XCTAssertEqual(history.count, ActionHistory.limit)
        XCTAssertEqual(history.first?.file, "newest.pdf", "the newest is never the one dropped")
    }

    // MARK: - Reading it back

    /// A store written by an older build, or a clock that moved: entries from
    /// the future must not be shown as if they happened.
    func testTheWindowIsAlsoReadWhenNothingIsBeingRecorded() {
        let entries = [entry("recent.pdf", at: 39), entry("stale.pdf", at: 1)]
        XCTAssertEqual(ActionHistory.within(entries, now: day(40)).map(\.file), ["recent.pdf"])
    }

    func testAnEmptyHistoryIsEmptyAndNotAnError() {
        XCTAssertTrue(ActionHistory.within([], now: day(40)).isEmpty)
        XCTAssertEqual(ActionHistory.summary(of: [], now: day(40)).total, 0)
    }

    // MARK: - The summary line

    func testTheSummaryCountsWhatActuallyHappened() {
        let entries = [
            entry("a.pdf", at: 39), entry("b.pdf", at: 38),
            entry("c.png", at: 37, .renamed, detail: "2026-07 c.png"),
            entry("d.zip", at: 36, .trashed, detail: ""),
            entry("e.txt", at: 35, .failed, detail: "no permission"),
        ]
        let summary = ActionHistory.summary(of: entries, now: day(40))
        XCTAssertEqual(summary.moved, 2)
        XCTAssertEqual(summary.renamed, 1)
        XCTAssertEqual(summary.trashed, 1)
        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.total, 5)
    }

    /// The summary must count the same entries the list shows, or the page says
    /// "17 files" above a list of nine.
    func testTheSummaryCountsOnlyWhatTheListShows() {
        let entries = [entry("in.pdf", at: 39), entry("out.pdf", at: 1)]
        let summary = ActionHistory.summary(of: entries, now: day(40))
        XCTAssertEqual(summary.total, ActionHistory.within(entries, now: day(40)).count)
        XCTAssertEqual(summary.total, 1)
    }

    // MARK: - Surviving the store

    func testARecordSurvivesBeingWrittenAndReadBack() throws {
        let original = [entry("a.pdf", at: 39),
                        entry("b.png", at: 38, .tagged, detail: "Invoice"),
                        entry("c.zip", at: 37, .refused, detail: "outOfScope")]
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode([ActionRecord].self, from: data), original)
    }

    /// The store outlives the build that wrote it. A record it cannot read must
    /// cost the reader nothing worse than a shorter history.
    func testAnUnreadableStoreIsAnEmptyHistoryRatherThanACrash() {
        XCTAssertTrue(ActionHistory.decode(Data("not json".utf8)).isEmpty)
        XCTAssertTrue(ActionHistory.decode(nil).isEmpty)
    }
}

/// The sweep and the watcher must read an outcome the same way.
final class ActionRecordFromOutcomeTests: XCTestCase {

    private let plan = RulePlan(
        facts: FileFacts(name: "march.pdf", path: "/Users/r/Downloads/march.pdf",
                         kind: .document, bytes: 1_000, added: Date(), modified: Date()),
        rule: Rule(name: "Invoices", enabled: true, match: .all, conditions: [], action: .trash))

    func testEachOutcomeBecomesTheRecordThePageShows() {
        let moved = ActionRecord.of(plan, .moved(to: "/Users/r/Documents/Invoices/march.pdf"))
        XCTAssertEqual(moved?.kind, .moved)
        XCTAssertEqual(moved?.detail, "Invoices", "the folder it landed in, not the whole path")
        XCTAssertEqual(moved?.file, "march.pdf")
        XCTAssertEqual(moved?.rule, "Invoices")

        XCTAssertEqual(ActionRecord.of(plan, .renamed(to: "2026-07 march.pdf"))?.detail,
                       "2026-07 march.pdf")
        XCTAssertEqual(ActionRecord.of(plan, .tagged("Paid"))?.detail, "Paid")
        XCTAssertEqual(ActionRecord.of(plan, .trashed)?.kind, .trashed)
        XCTAssertEqual(ActionRecord.of(plan, .trashed)?.detail, "")
        XCTAssertEqual(ActionRecord.of(plan, .refused(.outOfScope))?.detail, "outOfScope")
        XCTAssertEqual(ActionRecord.of(plan, .failed("no permission"))?.detail, "no permission")
    }

    /// A rule that matches a file it has already dealt with runs on every
    /// sweep. Recording that would bury the day's real work under it.
    func testAnActionThatDidNotHappenIsNotRemembered() {
        XCTAssertNil(ActionRecord.of(plan, .alreadyDone))
    }
}
