import XCTest
@testable import Module_Autopilot_Engine

/// The history's own doc says it answers "where did that go". It could not:
/// `detail` holds the destination's *parent folder name* — good to read, useless
/// to open — and `path` holds where the file was, which after a move is a path
/// nothing is at. Neither field can reach the file.
///
/// So a record now keeps the full destination too. The rule this file pins is
/// that it is either a path the action actually left the file at, or empty —
/// never a guess, because a reveal that silently does nothing is worse than a
/// row that offers none.
final class ActionHistoryDestinationTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_700_000_000)
    private let rule = Rule(id: "r", name: "Invoices", enabled: true,
                            action: .move(to: "/Users/x/Documents/Invoices"))

    private func plan(_ path: String) -> RulePlan {
        RulePlan(facts: FileFacts(name: (path as NSString).lastPathComponent, path: path,
                                  kind: .document, bytes: 1, added: when, modified: when,
                                  now: when),
                 rule: rule)
    }

    private func record(_ path: String, _ outcome: RuleOutcome) throws -> ActionRecord {
        try XCTUnwrap(ActionRecord.of(plan(path), outcome, at: when))
    }

    /// The case the section exists for. The short folder name stays exactly what
    /// the row draws today; the full path is the new, separate answer.
    func test_a_move_keeps_the_whole_destination_and_still_shows_the_folder() throws {
        let r = try record("/Users/x/Downloads/march.pdf",
                           .moved(to: "/Users/x/Documents/Invoices/march.pdf"))
        XCTAssertEqual(r.detail, "Invoices", "the row's short form changed")
        XCTAssertEqual(r.destination, "/Users/x/Documents/Invoices/march.pdf")
        XCTAssertEqual(r.revealPath, r.destination)
    }

    /// A rename leaves the file in its folder under a new name, and the name the
    /// runner reports is the one that landed — including the numbered form a
    /// collision produces. Rebuilt against the *original* parent, which is the
    /// only parent a rename has.
    func test_a_rename_points_at_the_new_name_in_the_same_folder() throws {
        let r = try record("/Users/x/Downloads/scan.pdf", .renamed(to: "Invoice 2025 2.pdf"))
        XCTAssertEqual(r.detail, "Invoice 2025 2.pdf")
        XCTAssertEqual(r.destination, "/Users/x/Downloads/Invoice 2025 2.pdf")
    }

    /// Tagging moves nothing, so the file is exactly where it was — the one case
    /// where the old `path` was already the answer.
    func test_a_tag_points_at_the_file_that_was_tagged() throws {
        let r = try record("/Users/x/Downloads/photo.jpg", .tagged("Holiday"))
        XCTAssertEqual(r.destination, "/Users/x/Downloads/photo.jpg")
    }

    /// The Trash renames what it takes when a name is occupied, so the path the
    /// file used to have is not where it is, and Helm never asked for the
    /// resulting URL. Nothing knowable, therefore nothing offered.
    func test_the_outcomes_that_leave_no_knowable_location_offer_nothing() throws {
        for outcome in [RuleOutcome.trashed,
                        .refused(.missing),
                        .refused(.outOfScope),
                        .failed("permission denied")] {
            let r = try record("/Users/x/Downloads/a.pdf", outcome)
            XCTAssertEqual(r.destination, "", "\(outcome)")
            XCTAssertNil(r.revealPath, "\(outcome)")
        }
    }

    /// `FileFacts.path` defaults to empty and plenty of call sites leave it so.
    /// A rename rebuilds the destination from the file's parent, and an empty
    /// parent makes `"" + "/" + name` — an absolute path at the root of the
    /// volume, pointing at nothing, or worse at whatever is called that. The
    /// rule is the same as everywhere else here: no location, no offer.
    func test_a_file_with_no_known_parent_is_not_given_one_at_the_root() throws {
        let facts = FileFacts(name: "scan.pdf", kind: .document, bytes: 1,
                              added: when, modified: when, now: when)
        let r = try XCTUnwrap(ActionRecord.of(RulePlan(facts: facts, rule: rule),
                                              .renamed(to: "Invoice.pdf"), at: when))
        XCTAssertEqual(r.destination, "", "offered /Invoice.pdf at the volume root")
        XCTAssertNil(r.revealPath)
    }

    /// The schema addition, migrated the way `path` was: a history written by
    /// the build before this one has no such key and must still decode, whole.
    func test_a_record_written_before_this_build_decodes_without_a_destination() throws {
        let json = """
        [{"at": 700000000, "rule": "Invoices", "file": "march.pdf",
          "path": "/Users/x/Downloads/march.pdf", "kind": "moved", "detail": "Invoices"}]
        """
        let history = ActionHistory.decode(Data(json.utf8))
        XCTAssertEqual(history.count, 1, "an older history was dropped entirely")
        XCTAssertEqual(history.first?.destination, "")
        XCTAssertNil(history.first?.revealPath)
        XCTAssertEqual(history.first?.detail, "Invoices")
    }

    /// And it survives its own round trip, or the reveal works until the app is
    /// relaunched — the sort of half-fix a green size assertion blesses.
    func test_the_destination_survives_encoding_and_decoding() throws {
        let r = try record("/Users/x/Downloads/march.pdf",
                           .moved(to: "/Users/x/Documents/Invoices/march.pdf"))
        let restored = ActionHistory.decode(ActionHistory.encode([r]))
        XCTAssertEqual(restored, [r])
        XCTAssertEqual(restored.first?.revealPath, "/Users/x/Documents/Invoices/march.pdf")
    }
}
