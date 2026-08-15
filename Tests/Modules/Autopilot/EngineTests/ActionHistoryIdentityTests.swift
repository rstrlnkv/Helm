import XCTest
@testable import Module_Autopilot_Engine

/// `PreviewRow.id` was changed today from the file's name to its path, because
/// "two files called `report.pdf` in two folders were two plans and one row —
/// so the screen a person reads before letting a rule loose hid a file the rule
/// was about to touch."
///
/// The history written on the same day records `plan.facts.name` and nothing
/// else, and then collapses records it considers repeats by
/// `kind + file + detail + rule`. Two different files that share a name are
/// indistinguishable to it — and unlike the preview, where the cost was a row
/// not drawn, here the newer record *deletes* the older one from the store.
///
/// A folder watched with `depth` set to include subfolders is the ordinary way
/// to get two of a name; `~/Downloads/2025/report.pdf` and
/// `~/Downloads/2026/report.pdf` need no contrivance at all.
final class ActionHistoryIdentityTests: XCTestCase {

    private func at(_ hour: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(hour) * 3_600) }

    private let rule = Rule(id: "r", name: "Sort downloads", enabled: true,
                            action: .move(to: "/Users/x/Documents"))

    private func facts(_ path: String) -> FileFacts {
        FileFacts(name: (path as NSString).lastPathComponent, path: path,
                  kind: .document, bytes: 1, added: at(0), modified: at(0), now: at(0))
    }

    /// Two files, two refusals, two things still sitting where they were. The
    /// page says "not completed: 1" and lists one row, and whichever of the two
    /// the person goes looking for, the report is about the other one.
    func test_two_files_of_one_name_refused_are_two_rows() throws {
        let first = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts("/Users/x/Downloads/2025/report.pdf"), rule: rule),
            .refused(.outOfScope), at: at(1)))
        let second = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts("/Users/x/Downloads/2026/report.pdf"), rule: rule),
            .refused(.outOfScope), at: at(2)))

        var history = ActionHistory.recording(first, into: [], now: at(2))
        history = ActionHistory.recording(second, into: history, now: at(2))

        XCTAssertEqual(history.count, 2,
                       "one refusal erased the other: two different files are stuck and the "
                       + "report knows about \(history.count)")
    }

    /// The same collapse seen where the page reads it: the headline over the
    /// list counts what the list holds, so it undercounts too.
    func test_the_summary_counts_both_stuck_files() throws {
        let first = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts("/Users/x/Downloads/a/invoice.pdf"), rule: rule),
            .failed("permission denied"), at: at(1)))
        let second = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts("/Users/x/Downloads/b/invoice.pdf"), rule: rule),
            .failed("permission denied"), at: at(2)))

        var history = ActionHistory.recording(first, into: [], now: at(2))
        history = ActionHistory.recording(second, into: history, now: at(2))

        XCTAssertEqual(ActionHistory.summary(of: history, now: at(2)).failed, 2)
    }

    /// A record has to be able to say which file it is about. `id` is what
    /// `ForEach` draws the report by, so two records that are about two files
    /// must not share one — the identity bug `PreviewRow` was fixed for.
    func test_a_record_identifies_the_file_it_is_about() throws {
        let a = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts("/Users/x/Downloads/2025/report.pdf"), rule: rule),
            .trashed(to: "/Users/x/.Trash/report.pdf"), at: at(3)))
        let b = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts("/Users/x/Downloads/2026/report.pdf"), rule: rule),
            .trashed(to: "/Users/x/.Trash/report 2.pdf"), at: at(3)))

        XCTAssertNotEqual(a.id, b.id,
                          "two files trashed in the same sweep share one identity: \(a.id)")
    }

    /// Guard against the obvious over-correction: the flood control the same
    /// change added must keep working. One file refused every hour is still one
    /// row, not twenty-four.
    func test_the_same_file_refused_twice_is_still_one_row() throws {
        let path = "/Users/x/Downloads/shortcut"
        let first = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts(path), rule: rule), .refused(.outOfScope), at: at(1)))
        let second = try XCTUnwrap(ActionRecord.of(
            RulePlan(facts: facts(path), rule: rule), .refused(.outOfScope), at: at(2)))

        var history = ActionHistory.recording(first, into: [], now: at(2))
        history = ActionHistory.recording(second, into: history, now: at(2))

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.at, at(2), "the newest of a repeat is the one kept")
    }
}
