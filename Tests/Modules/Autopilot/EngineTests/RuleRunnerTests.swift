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
        XCTAssertEqual(outcome, .targetOutOfScope)
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

    /// The act, not the record: a file that exists outside `WatchScope` is
    /// handed to the runner with a move and a rename whose destinations are
    /// fine, and it has to stay exactly where it was. Deleting the scope check
    /// at the top of `RuleRunner.run` leaves the refusal row's reason to the
    /// other tests; this one is red on the disk.
    func testAFileOutsideTheWatchScopeIsNotMovedOrRenamed() throws {
        let elsewhere = scratchDirectory("elsewhere")
        let file = try write("a.pdf", in: elsewhere)
        let destination = root.appendingPathComponent("Sorted")

        let moved = runner.run(plan(file, .move(to: destination.path)), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(moved, .refused(.outOfScope))
        XCTAssertTrue(exists(file.path), "the out-of-scope file was moved")
        XCTAssertFalse(exists(destination.appendingPathComponent("a.pdf").path),
                       "something arrived at the destination")

        let renamed = runner.run(plan(file, .rename(pattern: "{name}-final")), at: file.path, key: TestRuleKey.material)
        XCTAssertEqual(renamed, .refused(.outOfScope))
        XCTAssertTrue(exists(file.path), "the out-of-scope file was renamed")
        XCTAssertFalse(exists(elsewhere.appendingPathComponent("a-final.pdf").path))
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

    // MARK: - Idempotence, with the stamp taken away
    //
    // `RuleRunner.note` tolerates a stamp that will not stick, and says why: a
    // volume without extended attributes would otherwise be a volume where no rule
    // works. The sentence it leans on is that the action re-runs *idempotently* on
    // an unchanged file. Two actions did not, and neither needed a contrived
    // filesystem to reach — any volume that will not keep the attribute, or whose
    // AppleDouble `._name` sidecar something drops, and `WatchScope` deliberately
    // admits `/Volumes`. (exFAT, which this used to name, keeps it —
    // ARCHITECTURE.md § Autopilot.)
    //
    // So every test in this section runs a rule id that was never stamped, against a file
    // already sitting where that rule wants it. The stamp is not disabled; it is
    // simply not consulted, which is the state an unstampable volume is in on
    // every sweep. What must come back is `.alreadyDone`, and the folder must be
    // the same afterwards — a listing, not a count, because the failure these
    // describe is a file that still exists under a name nobody chose.

    private func unstampedPlan(_ url: URL, _ action: RuleAction, kind: FileKind = .document) -> RulePlan {
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

    // MARK: - Never stamped: sorting

    /// The one that buries somebody's file.
    ///
    /// `sortIntoSubfolder` computes its bucket from the folder the file is in
    /// right now, so a file already in `Images/` is offered `Images/Images/`.
    /// With the stamp doing its job that is never asked; without it the file
    /// goes one level deeper every hour, unattended, and writes a `moved` row
    /// into the history each time.
    func testAFileAlreadyInItsBucketIsNotSortedIntoAnotherOne() throws {
        let file = try write("Images/a.jpg", in: root)

        let outcome = runner.run(unstampedPlan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["Images", "Images/a.jpg"],
                       "the file was buried one bucket deeper")
    }

    /// The same for the month scheme, which names its bucket after a date
    /// rather than a kind and so cannot be got right by accident.
    func testAFileAlreadyInItsMonthFolderIsNotSortedAgain() throws {
        let file = try write("2026-07/a.pdf", in: root)

        let outcome = runner.run(unstampedPlan(file, .sortIntoSubfolder(.month)), at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["2026-07", "2026-07/a.pdf"])
    }

    /// And the case the rule is actually for still works: a file that is *not*
    /// in its bucket is put in it. Without this the fix above could be "never
    /// sort anything" and the tests would not notice.
    func testAFileThatIsNotInItsBucketIsStillSorted() throws {
        let file = try write("a.jpg", in: root)

        let outcome = runner.run(unstampedPlan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome, .moved(to: root.appendingPathComponent("Images/a.jpg").path))
        XCTAssertEqual(tree(), ["Images", "Images/a.jpg"])
    }

    /// A bucket nested inside another folder of the same name is still a file
    /// that has arrived: only the folder the file is *in* decides.
    func testOnlyTheFolderTheFileIsInCounts() throws {
        let file = try write("Images/Holiday/a.jpg", in: root)

        let outcome = runner.run(unstampedPlan(file, .sortIntoSubfolder(.kind), kind: .image), at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome,
                       .moved(to: root.appendingPathComponent("Images/Holiday/Images/a.jpg").path),
                       "the rule sorts within the folder each file sits in")
    }

    // MARK: - Never stamped: moving

    /// A rule whose destination is the folder its files are already in.
    ///
    /// "Every image goes to ~/Downloads", pointed at ~/Downloads — one wrong
    /// choice in the panel, and reachable without malice. `free()` then finds
    /// the file's own name taken, by the file itself, and numbers the arrival:
    /// `photo.jpg` becomes `photo 2.jpg`, and `photo 2 2.jpg` the sweep after
    /// that. `rename` has guarded this since it was written; `move` never did.
    func testMovingAFileIntoTheFolderItIsAlreadyInDoesNothing() throws {
        let file = try write("photo.jpg", in: root)

        let outcome = runner.run(unstampedPlan(file, .move(to: root.path), kind: .image), at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["photo.jpg"], "the file was renamed rather than left alone")
    }

    /// The same destination written with a trailing slash, which is how anyone
    /// typing a path writes a folder, and how a hand-edited plist is likely to
    /// carry one.
    func testATrailingSlashIsTheSameFolder() throws {
        let file = try write("photo.jpg", in: root)

        let outcome = runner.run(unstampedPlan(file, .move(to: root.path + "/"), kind: .image),
                                 at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome, .alreadyDone)
        XCTAssertEqual(tree(), ["photo.jpg"])
    }

    /// And a real move still moves.
    func testAMoveToSomewhereElseStillHappens() throws {
        let file = try write("photo.jpg", in: root)
        let elsewhere = root.appendingPathComponent("Sorted")

        let outcome = runner.run(unstampedPlan(file, .move(to: elsewhere.path), kind: .image), at: file.path, key: TestRuleKey.material)

        XCTAssertEqual(outcome, .moved(to: elsewhere.appendingPathComponent("photo.jpg").path))
        XCTAssertEqual(tree(), ["Sorted", "Sorted/photo.jpg"])
    }
}

/// Renaming, where the name the runner *reports* and the name it *produced* can
/// come apart.
///
/// `free(_:)` decides the name that actually gets used — `b.pdf` becomes
/// `b 2.pdf` when `b.pdf` is taken — but `run` reports, and stamps, the name the
/// pattern produced. Nothing else in the module notices, because the collision
/// case is the only one where the two differ. Every test here is that pair
/// agreeing, and the two failures a disagreement causes: a mark on a file
/// nobody touched, and no mark on the file that moved.
final class RuleRunnerRenameTests: XCTestCase {

    private var root: URL!
    private var home: URL!
    private var runner: RuleRunner!
    private let stamp = RuleStamp(key: TestRuleKey.material)

    override func setUpWithError() throws {
        // Inside a temporary directory the runner is told to treat as home:
        // `WatchScope` refuses anything outside one, and a test that wanted an
        // exemption from that gate would be testing a different program.
        home = scratchDirectory("home")
        root = home
            .appendingPathComponent("helm-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = RuleRunner(home: home.path)
    }

    private func rename(_ url: URL, pattern: String, id: String = "r") -> RuleOutcome {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: url.lastPathComponent, kind: .document, bytes: 4,
                              added: now, modified: now, now: now)
        let rule = Rule(id: id, name: id, enabled: true,
                        conditions: [.fileExtension(["pdf"])], action: .rename(pattern: pattern))
        return runner.run(RulePlan(facts: facts, rule: rule), at: url.path, key: TestRuleKey.material)
    }

    private func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    // MARK: - The name reported and the name on disk

    /// The root of the other two. `.renamed(to:)` is the only thing the sweep,
    /// the log and the stamp are told about a rename, so a name that is not on
    /// disk is a lie every one of them then acts on.
    func testTheNameAReportedRenameGivesIsTheNameOnDisk() throws {
        try write("b.pdf", in: root, bytes: 99)
        let file = try write("a.pdf", in: root)

        guard case let .renamed(to: reported) = rename(file, pattern: "b") else {
            return XCTFail("expected a rename")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(reported).path),
                      "the runner reported \(reported), which is not what it produced")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(reported)).count, 4,
                       "the reported name points at the file that was already there, not the one that moved")
    }

    /// The collateral damage. The stamp lands on `b.pdf` — a file this rule
    /// never acted on and, because it now carries the mark, never will.
    /// Switching a rule off and on again does not clear it; it is an xattr on
    /// somebody's file.
    func testACollidingRenameDoesNotStampTheFileItCollidedWith() throws {
        let bystander = try write("b.pdf", in: root, bytes: 99)
        let file = try write("a.pdf", in: root)

        _ = rename(file, pattern: "b")

        XCTAssertFalse(stamp.isStamped(bystander.path, by: "r"),
                       "a file the rule never acted on was marked as done")
        XCTAssertTrue(stamp.isStamped(root.appendingPathComponent("b 2.pdf").path, by: "r"),
                      "the file that was actually renamed carries no mark, so the rule will rename it again")
    }

    /// A pattern that resolves to the name the file already has.
    ///
    /// `{name}` is a legitimate thing to write — `{name} {date}` minus the date,
    /// or a pattern being edited. `free(_:)` sees the target is taken without
    /// noticing that the file taking it *is the file being renamed*, so `a.pdf`
    /// becomes `a 2.pdf`, and nothing is stamped because the path the stamp goes
    /// to no longer exists. Next hour: `a 2 2.pdf`.
    func testRenamingAFileToTheNameItAlreadyHasChangesNothing() throws {
        let file = try write("a.pdf", in: root)

        _ = rename(file, pattern: "{name}")
        XCTAssertEqual(try listing(), ["a.pdf"],
                       "a rename to the file's own name produced a numbered copy of the name")

        // Whatever shape the fix takes — a no-op, or a refusal — running again
        // must not add a file either. That is the part a sweep every hour turns
        // into a folder nobody can use.
        let remaining = try XCTUnwrap(listing().first)
        _ = rename(root.appendingPathComponent(remaining), pattern: "{name}", id: "r2")
        XCTAssertEqual(try listing(), ["a.pdf"])
    }

    // MARK: - Names the filesystem will not take

    /// 300 characters is past the 255-byte limit on a path component, so the
    /// move throws. What matters is that the file is where it was and is
    /// reported, rather than half-renamed or quietly counted as done.
    func testANameTooLongForTheFilesystemLeavesTheFileIntact() throws {
        let file = try write("a.pdf", in: root, bytes: 7)

        let outcome = rename(file, pattern: String(repeating: "x", count: 300))

        XCTAssertEqual(try listing(), ["a.pdf"])
        XCTAssertEqual(try Data(contentsOf: file).count, 7)
        if case .renamed = outcome { XCTFail("reported a rename that did not happen") }
        XCTAssertFalse(stamp.isStamped(file.path, by: "r"),
                       "a rename that failed must not be recorded as having happened")
    }

    /// Guarantee 5 as a property rather than as a handful of examples: whatever
    /// a pattern is, the answer is either nothing at all or one path component
    /// that keeps the file's own extension. The corpus is the awkward input
    /// list — empty, whitespace, separators, a leading dot, a tab, a newline,
    /// Cyrillic, an emoji, and something far too long.
    ///
    /// Note what this does *not* claim: a tab and a newline survive, because
    /// `RenamePattern` only refuses `/`, `:` and a leading dot. Both are legal
    /// on APFS. They are here so that a future filter is a deliberate change to
    /// this list rather than a surprise.
    func testWhateverAPatternProducesIsOneComponentWithTheFilesOwnExtension() {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: "a.pdf", kind: .document, bytes: 1,
                              added: now, modified: now, now: now)
        let corpus = ["", "   ", "\n\t ", ".", "..", "./x", "sub/{name}", "{name}/{date}",
                      "a:b", ".{name}", "{name}", "{name}{date}{counter}", "{unknown}",
                      "отчёт", "🙂", "a\tb", "a\nb", "  {name}  ", "{name}.txt",
                      String(repeating: "x", count: 300)]

        for pattern in corpus {
            guard let produced = RenamePattern.apply(pattern, to: facts) else { continue }
            XCTAssertFalse(produced.isEmpty, "\(pattern.debugDescription) produced an empty name")
            XCTAssertFalse(produced.contains("/"),
                           "\(pattern.debugDescription) produced a path, not a name")
            XCTAssertFalse(produced.contains(":"),
                           "\(pattern.debugDescription) produced a name the Finder reads as a path")
            XCTAssertFalse(produced.hasPrefix("."),
                           "\(pattern.debugDescription) produced a hidden file")
            XCTAssertEqual((produced as NSString).pathExtension, "pdf",
                           "\(pattern.debugDescription) changed what kind of file this is")
        }
    }
}

/// The sibling of `testRenamingAFileToTheNameItAlreadyHasChangesNothing`.
///
/// That case is guarded by `target.path != url.path` — a string comparison. A
/// Mac's own volume is case-insensitive: `report.pdf` and `REPORT.pdf` are two
/// spellings the filesystem treats as one name, and the string comparison
/// cannot see it. So a rule that only changes capitalisation walks past the
/// guard, `free(_:)` then finds the "collision" (which is the file itself), and
/// numbers it.
///
/// Normalising names is one of the two or three things anybody writes a rename
/// rule for.
final class RuleRunnerCaseRenameTests: XCTestCase {

    private var root: URL!
    private var home: URL!
    private var runner: RuleRunner!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        runner = RuleRunner(home: home.path)

        // The defect only exists where the volume folds case, which is the
        // default on a Mac. On a case-sensitive volume the two names are two
        // files and the numbering would be correct.
        let probe = root.appendingPathComponent("case-probe")
        try Data("x".utf8).write(to: probe)
        let folded = FileManager.default
            .fileExists(atPath: root.appendingPathComponent("CASE-PROBE").path)
        try FileManager.default.removeItem(at: probe)
        try XCTSkipUnless(folded, "case-sensitive volume: these two names are two files")
    }

    private func rename(_ url: URL, pattern: String) -> RuleOutcome {
        let now = Date(timeIntervalSince1970: 1_784_116_800)
        let facts = FileFacts(name: url.lastPathComponent, path: url.path, kind: .document,
                              bytes: 4, added: now, modified: now, now: now)
        let rule = Rule(id: "r", name: "Tidy names", enabled: true,
                        conditions: [.fileExtension(["pdf"])],
                        action: .rename(pattern: pattern))
        return runner.run(RulePlan(facts: facts, rule: rule), at: url.path, key: TestRuleKey.material)
    }

    private func listing() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
    }

    func testRenamingAFileToADifferentSpellingOfItsOwnNameDoesNotNumberIt() throws {
        let file = root.appendingPathComponent("report.pdf")
        try Data(repeating: 0x41, count: 4).write(to: file)

        let outcome = rename(file, pattern: "REPORT")

        let onDisk = try listing()
        XCTAssertEqual(onDisk, ["REPORT.pdf"],
                       "the rule asked for REPORT.pdf; \(onDisk) is what it got")
        XCTAssertEqual(outcome, .renamed(to: "REPORT.pdf"))
    }
}
