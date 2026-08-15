import Foundation
import XCTest
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// Where the plan meets the disk.
///
/// Everything above this is arithmetic; this is the part that moves somebody's
/// files. So the tests are about what must not happen as much as what must:
/// a collision that overwrites, a destination outside the user's own files, a
/// second run that acts on the same file again.
final class RuleRunnerTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var runner: RuleRunner!

    /// The fixtures sit inside a temporary directory that the runner is told to
    /// treat as the home directory. `WatchScope` refuses anything outside a
    /// home, which is the point of it — so a test that wants to exercise the
    /// runner has to give it one rather than be exempted from the gate.
    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = RuleRunner(home: home.path)
    }

    private func facts(_ url: URL, kind: FileKind = .document) -> FileFacts {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return FileFacts(name: url.lastPathComponent, kind: kind, bytes: 4,
                         added: now, modified: now, now: now)
    }

    private func plan(_ url: URL, _ action: RuleAction, id: String = "r",
                      kind: FileKind = .document) -> RulePlan {
        RulePlan(facts: facts(url, kind: kind),
                 rule: Rule(id: id, name: id, enabled: true,
                            conditions: [.name(.contains, "")], action: action))
    }

    private var exists: (String) -> Bool { FileManager.default.fileExists(atPath:) }

    // MARK: - Moving

    func testMoveIntoAnotherFolder() throws {
        let file = try write("a.pdf", in: root)
        let destination = root.appendingPathComponent("Sorted")
        let outcome = runner.run(plan(file, .move(to: destination.path)), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(outcome, .moved(to: destination.appendingPathComponent("a.pdf").path))
        XCTAssertFalse(exists(file.path))
        XCTAssertTrue(exists(destination.appendingPathComponent("a.pdf").path))
    }

    /// The destination folder is created rather than the move failing: a rule
    /// that names a folder is asking for that folder to exist.
    func testTheDestinationIsCreated() throws {
        let file = try write("a.pdf", in: root)
        let deep = root.appendingPathComponent("One/Two/Three")
        _ = runner.run(plan(file, .move(to: deep.path)), at: file.path, key: TestRuleKey.material)
        XCTAssertTrue(exists(deep.appendingPathComponent("a.pdf").path))
    }

    /// The one that would lose somebody's work. A file already at the
    /// destination is never overwritten; the arriving one is numbered.
    func testACollisionIsNumberedRatherThanOverwritten() throws {
        let file = try write("a.pdf", in: root, bytes: 4)
        let destination = root.appendingPathComponent("Sorted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 99).write(to: destination.appendingPathComponent("a.pdf"))

        _ = runner.run(plan(file, .move(to: destination.path)), at: file.path, key: TestRuleKey.material)

        let kept = try Data(contentsOf: destination.appendingPathComponent("a.pdf"))
        XCTAssertEqual(kept.count, 99, "the file that was already there was overwritten")
        XCTAssertTrue(exists(destination.appendingPathComponent("a 2.pdf").path))
    }

    /// A rule cannot be used to move a file somewhere it has no business being,
    /// however the destination got into the rule.
    func testADestinationOutsideTheUsersFilesIsRefused() throws {
        let file = try write("a.pdf", in: root)
        let outcome = runner.run(plan(file, .move(to: "/System/Library/Helm")), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(outcome, .refused(.outOfScope))
        XCTAssertTrue(exists(file.path), "the file was moved anyway")
    }

    // MARK: - Sorting and renaming

    func testSortIntoSubfolderByKind() throws {
        let file = try write("a.png", in: root)
        _ = runner.run(plan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path, key: TestRuleKey.material)
        XCTAssertTrue(exists(root.appendingPathComponent("Images/a.png").path))
    }

    func testSortIntoSubfolderByMonth() throws {
        let file = try write("a.pdf", in: root)
        _ = runner.run(plan(file, .sortIntoSubfolder(.month)), at: file.path, key: TestRuleKey.material)
        XCTAssertTrue(exists(root.appendingPathComponent("2026-07/a.pdf").path))
    }

    func testRename() throws {
        let file = try write("report.pdf", in: root)
        let outcome = runner.run(plan(file, .rename(pattern: "{name}-final")), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(outcome, .renamed(to: "report-final.pdf"))
        XCTAssertTrue(exists(root.appendingPathComponent("report-final.pdf").path))
    }

    /// A pattern the filesystem should not be asked to take leaves the file
    /// alone and says so, rather than half-renaming it.
    func testARefusedPatternLeavesTheFileAlone() throws {
        let file = try write("report.pdf", in: root)
        let outcome = runner.run(plan(file, .rename(pattern: "../{name}")), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(outcome, .refused(.badPattern))
        XCTAssertTrue(exists(file.path))
    }

    // MARK: - Trash

    /// Deletion goes through the same gate as every other module's, inside the
    /// engine, not in the view model that built the plan.
    ///
    /// **This trashes for real**, so the leaf carries a UUID nobody else could
    /// own and the teardown takes it back out — and the outcome now names where
    /// the Trash put it, which is what the undo fetches back.
    func testTrashGoesThroughTheUserFileGate() throws {
        let leaf = unownableLeaf("a.pdf")
        reclaimFromTrash(leaf)
        let file = try write(leaf, in: root)
        let outcome = runner.run(plan(file, .trash), at: file.path, key: TestRuleKey.material)

        guard case let .trashed(to: bin) = outcome else {
            return XCTFail("expected a trashing, got \(outcome)")
        }
        XCTAssertFalse(exists(file.path))
        XCTAssertTrue(exists(bin), "the outcome names a path nothing is at: \(bin)")
        XCTAssertNotEqual(bin, file.path, "the Trash was said to hold the path the file had")
    }

    func testTrashingSomethingOutOfScopeIsRefused() {
        let outcome = runner.run(plan(URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc"),
                                      .trash),
                                 at: "/System/Library/Fonts/Helvetica.ttc", key: TestRuleKey.material)
        XCTAssertEqual(outcome, .refused(.outOfScope))
    }

    // MARK: - Running twice

    /// The same rule over the same file a second time does nothing.
    ///
    /// This used to say it was `RuleStamp` seen from the outside, and it is not
    /// any more: the second run is a move into the folder the file is already
    /// in, which `RuleRunner.move` now refuses on its own. Deleting the stamp
    /// guard leaves this green. What the stamp is still the only answer to is
    /// tagging and renaming, and those are covered in `AutopilotSweepTests`.
    func testARuleDoesNotActOnTheSameFileTwice() throws {
        let file = try write("a.pdf", in: root)
        let destination = root.appendingPathComponent("Sorted")
        let first = runner.run(plan(file, .move(to: destination.path)), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(first, .moved(to: destination.appendingPathComponent("a.pdf").path))

        let landed = destination.appendingPathComponent("a.pdf")
        let second = runner.run(plan(landed, .move(to: destination.path)), at: landed.path, key: TestRuleKey.material)
        XCTAssertEqual(second, .alreadyDone)
    }

    /// A different rule is not blocked by the first one's mark.
    func testAnotherRuleStillGetsItsTurn() throws {
        let file = try write("a.pdf", in: root)
        _ = runner.run(plan(file, .addTag("one"), id: "rule-1"), at: file.path, key: TestRuleKey.material)
        let outcome = runner.run(plan(file, .addTag("two"), id: "rule-2"), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(outcome, .tagged("two"))
    }
}
