import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// **The knot the whole feature turns on**, and the only test of it: a file
/// taken out of the Trash comes back *clean*, because nothing stamps a file it
/// has just binned — so the rule that binned it matches it again on the next
/// sweep, within the hour, with nobody watching. Give a person their file back
/// and let Autopilot take it away again and the return is worse than no return.
///
/// So the return marks the file for the rule that acted, and this asserts the
/// consequence rather than the mechanism: the same rule, run again on the same
/// file, reports `.alreadyDone`.
///
/// **Everything here is real** — the real `trashItem`, the real `~/.Trash`, the
/// real extended attribute — because every one of those is a place the chain
/// could break. That is also why the folder sits inside the real home
/// directory: `WatchScope` measures against a home, and the Trash a file goes
/// to is inside one. A scratch folder in `$TMPDIR` with a made-up home would
/// have the return refuse its own Trash, which is a test of nothing.
final class AReturnFromTheTrashKeepsTheMarkTests: XCTestCase {

    private var folder: URL!
    private var leaf: String!
    private let key = TestRuleKey.material
    private let ruleID = "rule-bin"
    private var home: String { NSHomeDirectory() }

    /// A directory in the real home, gone when the test is.
    ///
    /// Not `scratchDirectory`, which is `$TMPDIR` by construction, and not its
    /// draining teardown either: the drain exists for a write arriving from
    /// somebody's own task after the test ends, and nothing here is
    /// asynchronous. What is kept is its assertion — a teardown that cannot
    /// fail is how 7621 directories accumulated.
    private func folderInTheRealHome() -> URL {
        let url = URL(fileURLWithPath: home)
            .appendingPathComponent(".helm-undo-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                           "the test left \(url.lastPathComponent) in the home directory")
        }
        return url
    }

    override func setUpWithError() throws {
        folder = folderInTheRealHome()
        // Trashed for real, so the name is one nobody else could own and the
        // teardown takes it back out if the return does not.
        leaf = unownableLeaf("invoice.pdf")
        reclaimFromTrash(leaf)
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    private func plan(_ url: URL) -> RulePlan {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return RulePlan(facts: FileFacts(name: url.lastPathComponent, path: url.path,
                                         kind: .document, bytes: 7, added: now,
                                         modified: now, now: now),
                        rule: Rule(id: ruleID, name: "Old downloads", enabled: true,
                                   conditions: [.name(.contains, "")], action: .trash))
    }

    func testAFileFetchedBackOutOfTheTrashIsNotBinnedAgain() throws {
        let file = try write(leaf, in: folder)
        let runner = RuleRunner(home: home)
        let plan = plan(file)

        guard case let .trashed(to: bin) = runner.run(plan, at: file.path, key: key) else {
            return XCTFail("the file was never binned, so nothing below proves anything")
        }
        XCTAssertFalse(exists(file.path), "the file is still where it was")
        XCTAssertTrue(exists(bin), "the Trash does not hold the file the outcome names")

        let record = try XCTUnwrap(ActionRecord.of(plan, .trashed(to: bin), run: "pass-1"))
        XCTAssertEqual(record.destination, bin)

        let outcome = UndoRunner(home: home).undo(record, key: key)

        XCTAssertEqual(outcome, .restored(to: file.path, stamped: true))
        XCTAssertTrue(exists(file.path), "the file did not come back")
        XCTAssertFalse(exists(bin), "the file is back and also still in the Trash")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "AAAA",
                       "something came back and it was not the file")

        // The knot. Without the mark the rule matches this file again — it
        // matches every name — and the person's file goes straight back into
        // the Trash on the next sweep.
        XCTAssertEqual(runner.run(plan, at: file.path, key: key), .alreadyDone,
                       "the rule binned the file it had just been asked to give back")
    }

    /// The mark is the rule's own, so another rule is not silenced by it. The
    /// return is not a way to make a folder immune to Autopilot.
    func testTheMarkTheReturnLeavesBelongsToOneRuleOnly() throws {
        let file = try write(leaf, in: folder)
        let runner = RuleRunner(home: home)
        let binning = plan(file)

        guard case let .trashed(to: bin) = runner.run(binning, at: file.path, key: key) else {
            return XCTFail("the file was never binned, so nothing below proves anything")
        }
        let record = try XCTUnwrap(ActionRecord.of(binning, .trashed(to: bin), run: "pass-1"))
        XCTAssertEqual(UndoRunner(home: home).undo(record, key: key),
                       .restored(to: file.path, stamped: true))

        let another = RulePlan(facts: binning.facts,
                               rule: Rule(id: "rule-tag", name: "Mark them", enabled: true,
                                          conditions: [.name(.contains, "")],
                                          action: .addTag("Seen")))
        XCTAssertEqual(runner.run(another, at: file.path, key: key), .tagged("Seen"))
    }
}
