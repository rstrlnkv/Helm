import XCTest
import HelmRuntime
@testable import Module_Autopilot_Engine

/// A record that cannot be put back is a report.
///
/// A record carries four things, each a way an undo would otherwise move the
/// wrong file: the pass it belonged to, the rule's **id**
/// (names are not unique, and a stamp is keyed by id), who the file is, and
/// whether it has been put back already. All four are Optional, because the
/// store outlives the build that wrote it.
final class ARecordSaysWhatItTookTests: XCTestCase {

    private let when = Date(timeIntervalSince1970: 1_700_000_000)
    private let rule = Rule(id: "rule-7", name: "Invoices", enabled: true,
                            action: .move(to: "/Users/x/Documents/Invoices"))

    private func plan(_ path: String) -> RulePlan {
        RulePlan(facts: FileFacts(name: (path as NSString).lastPathComponent, path: path,
                                  kind: .document, bytes: 1, added: when, modified: when,
                                  now: when),
                 rule: rule)
    }

    private func record(_ outcome: RuleOutcome, run: String = "pass-1",
                        identify: @escaping (String) -> PathCanonical.FileIdentity?
                            = { _ in PathCanonical.FileIdentity(device: 3, inode: 44) })
        throws -> ActionRecord {
        try XCTUnwrap(ActionRecord.of(plan("/Users/x/Downloads/march.pdf"), outcome,
                                      at: when, run: run, identify: identify))
    }

    /// The rule's **id**, not only its name. Two rules may share a name; the
    /// stamp a return re-writes is keyed by the id, so a return that had only
    /// the name could stamp the wrong rule and hand the file straight back to
    /// the one that took it.
    func testARecordNamesTheRuleByIdAndThePassItBelongedTo() throws {
        let r = try record(.moved(to: "/Users/x/Documents/Invoices/march.pdf"))
        XCTAssertEqual(r.ruleID, "rule-7")
        XCTAssertEqual(r.rule, "Invoices", "the name the row shows changed")
        XCTAssertEqual(r.run, "pass-1")
    }

    /// Identity is who is at the destination, whatever the action was — one
    /// rule, no branching. The destination is where the file *is*, so the
    /// question "is this still the file Helm acted on" has one form.
    func testIdentityIsTakenOfTheFileTheActionLeftBehind() throws {
        var asked: [String] = []
        let r = try record(.moved(to: "/Users/x/Documents/Invoices/march.pdf"),
                           identify: { path in
                               asked.append(path)
                               return PathCanonical.FileIdentity(device: 1, inode: 2)
                           })
        XCTAssertEqual(asked, ["/Users/x/Documents/Invoices/march.pdf"])
        XCTAssertEqual(r.device, 1)
        XCTAssertEqual(r.inode, 2)
    }

    /// The Trash renames what it takes, so the resulting URL is the only thing
    /// that can find the file again — and it is the destination, so identity
    /// follows it without a special case.
    func testATrashedFileIsIdentifiedWhereTheTrashPutIt() throws {
        var asked: [String] = []
        let r = try record(.trashed(to: "/Users/x/.Trash/march 2.pdf"),
                           identify: { path in
                               asked.append(path)
                               return PathCanonical.FileIdentity(device: 1, inode: 9)
                           })
        XCTAssertEqual(r.destination, "/Users/x/.Trash/march 2.pdf")
        XCTAssertEqual(asked, ["/Users/x/.Trash/march 2.pdf"])
        XCTAssertEqual(r.inode, 9)
    }

    /// A refusal and a failure left the file wherever it was and the module does
    /// not know where that is. No destination, so nothing to identify, so
    /// nothing to offer — the same rule that governs the reveal.
    func testAnOutcomeThatMovedNothingCarriesNoIdentity() throws {
        for outcome in [RuleOutcome.refused(.outOfScope), .failed("permission denied")] {
            var asked = 0
            let r = try record(outcome, identify: { _ in
                asked += 1
                return PathCanonical.FileIdentity(device: 1, inode: 2)
            })
            XCTAssertEqual(asked, 0, "\(outcome): a path nothing is at was stat'ed")
            XCTAssertNil(r.device, "\(outcome)")
            XCTAssertNil(r.inode, "\(outcome)")
        }
    }

    /// A file refused for lying outside the allowed folders is by definition
    /// somewhere the person did not mean a rule to go, so the row says the reason
    /// and the rule and nothing about the file. A refusal for any other reason
    /// keeps its file: that one is the person's own, in plain sight.
    func testAScopeRefusalNamesNoFileAndNoPath() throws {
        let scope = try record(.refused(.outOfScope))
        XCTAssertEqual(scope.file, "")
        XCTAssertEqual(scope.path, "")

        let other = try record(.refused(.missing))
        XCTAssertEqual(other.file, "march.pdf")
    }

    /// A file on a volume that will not answer. The record is still written —
    /// the history's job is to say what happened — and it simply cannot be put
    /// back, which the undo reports as `noIdentity` rather than guessing.
    func testAFileThatCannotBeIdentifiedStillGetsARow() throws {
        let r = try record(.tagged("Holiday"), identify: { _ in nil })
        XCTAssertNil(r.device)
        XCTAssertFalse(r.undoable, "a record with no identity was offered a return")
    }

    /// Which rows the menu appears on, decided by the record's own shape rather
    /// than by a stat per row: the page draws five hundred of these.
    func testOnlyARecordWithSomewhereToGoBackToCanBePutBack() throws {
        let moved = try record(.moved(to: "/Users/x/Documents/Invoices/march.pdf"))
        XCTAssertTrue(moved.undoable)
        XCTAssertFalse(try record(.refused(.missing)).undoable)
        XCTAssertFalse(moved.undone(at: when).undoable, "a returned row offered a second return")
    }

    /// The store outlives the build: a history an older build wrote lacks the
    /// newer fields, and a decoder that threw on one would throw away the
    /// *whole* document (`JSONDecoder` gives up on the file, not on the key).
    func testAHistoryWrittenBeforeThisBuildStillDecodes() throws {
        let json = """
        [{"at": 700000000, "rule": "Invoices", "file": "march.pdf",
          "path": "/Users/x/Downloads/march.pdf", "kind": "moved",
          "detail": "Invoices", "destination": "/Users/x/Documents/Invoices/march.pdf"}]
        """
        let history = ActionHistory.decode(Data(json.utf8))
        XCTAssertEqual(history.count, 1, "an older history was dropped entirely")
        let first = try XCTUnwrap(history.first)
        XCTAssertEqual(first.destination, "/Users/x/Documents/Invoices/march.pdf")
        XCTAssertNil(first.run)
        XCTAssertNil(first.ruleID)
        XCTAssertNil(first.device)
        XCTAssertNil(first.inode)
        XCTAssertNil(first.undoneAt)
        XCTAssertFalse(first.undoable, "a record from before identity was recorded was offered a return")
    }

    func testTheNewFieldsSurviveEncodingAndDecoding() throws {
        let r = try record(.moved(to: "/Users/x/Documents/Invoices/march.pdf")).undone(at: when)
        XCTAssertEqual(ActionHistory.decode(ActionHistory.encode([r])), [r])
    }
}
