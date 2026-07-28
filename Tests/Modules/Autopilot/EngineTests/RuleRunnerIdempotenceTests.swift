import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// Idempotence, with the stamp taken away.
///
/// `RuleRunner.note` tolerates a stamp that will not stick, and says why: a
/// volume without extended attributes would otherwise be a volume where no rule
/// works. The sentence it leans on is that the action re-runs *idempotently* on
/// an unchanged file. Two actions did not, and neither needed a contrived
/// filesystem to reach — `setxattr` answers `ENOTSUP` on exFAT, which is the
/// format of most USB sticks, and `WatchScope` deliberately admits `/Volumes`.
///
/// So every test here runs a rule id that was never stamped, against a file
/// already sitting where that rule wants it. The stamp is not disabled; it is
/// simply not consulted, which is the state an unstampable volume is in on
/// every sweep. What must come back is `.alreadyDone`, and the folder must be
/// the same afterwards — a listing, not a count, because the failure these
/// describe is a file that still exists under a name nobody chose.
final class RuleRunnerIdempotenceTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var runner: RuleRunner!

    override func setUpWithError() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-home-\(UUID().uuidString)")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = RuleRunner(home: home.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int = 4) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    private func plan(_ url: URL, _ action: RuleAction, kind: FileKind = .document) -> RulePlan {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        return RulePlan(facts: FileFacts(name: url.lastPathComponent, kind: kind, bytes: 4,
                                         added: now, modified: now, now: now),
                        rule: Rule(id: "never-stamped-\(UUID().uuidString)", name: "r",
                                   enabled: true,
                                   conditions: [.name(.contains, "")], action: action))
    }

    /// Every path under `root`, relative and sorted. A folder described by its
    /// contents rather than by a count of them.
    private func tree() -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }

    // MARK: - Sorting

    /// The one that buries somebody's file.
    ///
    /// `sortIntoSubfolder` computes its bucket from the folder the file is in
    /// right now, so a file already in `Images/` is offered `Images/Images/`.
    /// With the stamp doing its job that is never asked; without it the file
    /// goes one level deeper every hour, unattended, and writes a `moved` row
    /// into the history each time.
    func testAFileAlreadyInItsBucketIsNotSortedIntoAnotherOne() throws {
        let file = try write("Images/a.jpg")

        let outcome = runner.run(plan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["Images", "Images/a.jpg"],
                       "the file was buried one bucket deeper")
    }

    /// The same for the month scheme, which names its bucket after a date
    /// rather than a kind and so cannot be got right by accident.
    func testAFileAlreadyInItsMonthFolderIsNotSortedAgain() throws {
        let file = try write("2026-07/a.pdf")

        let outcome = runner.run(plan(file, .sortIntoSubfolder(.month)), at: file.path)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["2026-07", "2026-07/a.pdf"])
    }

    /// And the case the rule is actually for still works: a file that is *not*
    /// in its bucket is put in it. Without this the fix above could be "never
    /// sort anything" and the tests would not notice.
    func testAFileThatIsNotInItsBucketIsStillSorted() throws {
        let file = try write("a.jpg")

        let outcome = runner.run(plan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path)

        XCTAssertEqual(outcome, .moved(to: root.appendingPathComponent("Images/a.jpg").path))
        XCTAssertEqual(tree(), ["Images", "Images/a.jpg"])
    }

    /// A bucket nested inside another folder of the same name is still a file
    /// that has arrived: only the folder the file is *in* decides.
    func testOnlyTheFolderTheFileIsInCounts() throws {
        let file = try write("Images/Holiday/a.jpg")

        let outcome = runner.run(plan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path)

        XCTAssertEqual(outcome,
                       .moved(to: root.appendingPathComponent("Images/Holiday/Images/a.jpg").path),
                       "the rule sorts within the folder each file sits in")
    }

    // MARK: - Moving

    /// A rule whose destination is the folder its files are already in.
    ///
    /// "Every image goes to ~/Downloads", pointed at ~/Downloads — one wrong
    /// choice in the panel, and reachable without malice. `free()` then finds
    /// the file's own name taken, by the file itself, and numbers the arrival:
    /// `photo.jpg` becomes `photo 2.jpg`, and `photo 2 2.jpg` the sweep after
    /// that. `rename` has guarded this since it was written; `move` never did.
    func testMovingAFileIntoTheFolderItIsAlreadyInDoesNothing() throws {
        let file = try write("photo.jpg")

        let outcome = runner.run(plan(file, .move(to: root.path), kind: .image), at: file.path)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["photo.jpg"], "the file was renamed rather than left alone")
    }

    /// The same destination written with a trailing slash, which is how anyone
    /// typing a path writes a folder, and how a hand-edited plist is likely to
    /// carry one.
    func testATrailingSlashIsTheSameFolder() throws {
        let file = try write("photo.jpg")

        let outcome = runner.run(plan(file, .move(to: root.path + "/"), kind: .image),
                                 at: file.path)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["photo.jpg"])
    }

    /// And a real move still moves.
    func testAMoveToSomewhereElseStillHappens() throws {
        let file = try write("photo.jpg")
        let elsewhere = root.appendingPathComponent("Sorted")

        let outcome = runner.run(plan(file, .move(to: elsewhere.path), kind: .image), at: file.path)

        XCTAssertEqual(outcome, .moved(to: elsewhere.appendingPathComponent("photo.jpg").path))
        XCTAssertEqual(tree(), ["Sorted", "Sorted/photo.jpg"])
    }
}
