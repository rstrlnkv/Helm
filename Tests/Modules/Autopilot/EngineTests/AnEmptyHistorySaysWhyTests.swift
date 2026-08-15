import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// **«Autopilot has not done anything yet» is three different sentences.**
///
/// It was one, and the other two were the ones worth saying: a Mac with no
/// watched folder is being told the module is idle when what it is, is
/// unconfigured; a rule set whose every rule is switched off says the same
/// thing, and the person switched them off. Only the third — folders watched,
/// rules running, nothing has matched — is the sentence that was being drawn,
/// and it is the one that needs the explanation about the hour.
///
/// The reasons are computed over the **passes**, not the raw records: the
/// section draws groups now, and a history whose every record has fallen out of
/// the thirty-day window draws nothing while `history.isEmpty` is false.
final class AnEmptyHistorySaysWhyTests: XCTestCase {

    private func rule(enabled: Bool) -> Rule {
        Rule(id: "r", name: "r", enabled: enabled,
             conditions: [.fileExtension(["pdf"])], action: .trash)
    }

    private func folder(enabled: Bool = true, rules: [Rule]) -> WatchedFolder {
        WatchedFolder(id: "f", path: "/Users/x/Downloads", enabled: enabled, rules: rules)
    }

    private func record(_ at: Date) -> ActionRecord {
        ActionRecord(at: at, rule: "r", file: "a.pdf", kind: .trashed, detail: "",
                     path: "/Users/x/Downloads/a.pdf", run: "run")
    }

    private func pass() -> ActionRun {
        ActionRun(id: "run", at: Date(), folder: "/Users/x/Downloads",
                  records: [record(Date())])
    }

    // MARK: - The control

    /// Asserted first, and it is the assertion the other four rest on: a history
    /// with something in it has no empty state at all, so «no reason» is a state
    /// this function really can be in.
    func testAHistoryWithAPassInItHasNoEmptyState() {
        XCTAssertNil(HistoryEmpty.reason(folders: [folder(rules: [rule(enabled: true)])],
                                         runs: [pass()]))
    }

    // MARK: - The three

    /// Nothing is watched. The module is not idle, it is unconfigured — and the
    /// screen has presets on it, which is a different thing to say than «files
    /// are checked once an hour».
    func testNoFoldersIsItsOwnReason() {
        XCTAssertEqual(HistoryEmpty.reason(folders: [], runs: []), .noFolders)
    }

    /// Folders watched, and not one rule that could run. Told, because the
    /// person did it and may not remember doing it — and because nothing will
    /// ever appear here until they undo it.
    func testEveryRuleSwitchedOffIsItsOwnReason() {
        XCTAssertEqual(HistoryEmpty.reason(folders: [folder(rules: [rule(enabled: false)])],
                                           runs: []),
                       .everyRuleOff)
    }

    /// A folder's own switch is above its rules', so a folder switched off runs
    /// none of them however they are set. The same sentence, because it is the
    /// same fact for the reader.
    func testAFolderSwitchedOffCountsAsEveryRuleOff() {
        XCTAssertEqual(HistoryEmpty.reason(folders: [folder(enabled: false,
                                                            rules: [rule(enabled: true)])],
                                           runs: []),
                       .everyRuleOff)
    }

    /// A folder with no rules in it yet is the same state read from one step
    /// earlier: nothing can run.
    func testAFolderWithNoRulesCountsAsEveryRuleOff() {
        XCTAssertEqual(HistoryEmpty.reason(folders: [folder(rules: [])], runs: []),
                       .everyRuleOff)
    }

    /// Everything is set up and nothing has happened. **This** is the sentence
    /// the module used to say in all three cases, and the only one where the
    /// explanation about files arriving and the hourly sweep is an answer.
    func testAWatchedFolderWithARunningRuleHasSimplyDoneNothingYet() {
        XCTAssertEqual(HistoryEmpty.reason(folders: [folder(rules: [rule(enabled: true)])],
                                           runs: []),
                       .nothingYet)
    }

    // MARK: - What the grouping changed

    /// **A history is not empty and the section still draws nothing.** The rows
    /// are grouped into passes and the grouping drops everything past thirty
    /// days, so a Mac that was tidied two months ago and not since has records
    /// in its store and no passes on its screen. Reading `history.isEmpty` there
    /// leaves the card blank with no sentence in it at all.
    func testAHistoryWhoseRecordsAreAllTooOldStillGetsASentence() {
        let ancient = [record(Date(timeIntervalSinceNow: -60 * 86_400))]
        let runs = ActionHistory.runs(of: ancient)
        XCTAssertFalse(ancient.isEmpty, "precondition: there are records in the store")
        XCTAssertTrue(runs.isEmpty, "precondition: and the section draws none of them")

        XCTAssertEqual(HistoryEmpty.reason(folders: [folder(rules: [rule(enabled: true)])],
                                           runs: runs),
                       .nothingYet,
                       "the reason is computed over the passes the section draws")
    }
}
