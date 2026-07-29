import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// A whole sweep, over a real folder, twice.
///
/// The unit tests below this level each hold one piece still: the matcher gets
/// facts, the runner gets a plan and a path. A sweep is the only place the two
/// meet, and it is where the path a plan refers to is *reconstructed* rather
/// than carried — `AutopilotEngine.sweep` joins the watched folder to
/// `plan.facts.name`, and `FileFacts` only ever holds a last path component.
/// Everything here is about that join.
///
/// The invariant these lean on is deliberately structural: which file exists
/// after a sweep, and whether a second sweep changes anything. A count or a
/// byte total can be satisfied by the wrong file being acted on; a listing
/// cannot.
final class AutopilotSweepTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        // Inside a temporary directory the runner is told to treat as home:
        // `WatchScope` refuses anything outside one, and a test that wanted an
        // exemption from that gate would be testing a different program.
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-home-\(UUID().uuidString)")
        root = home
            .appendingPathComponent("helm-sweep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // `keys` is a double for the same reason `home` is one: the real port
        // writes to the user's login keychain, and a test suite leaves nothing
        // behind. The seal itself is not stubbed out — these sweeps save and
        // read their rules through it exactly as the app does.
        engine = AutopilotEngine(store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                                    backing: InMemoryKeyValueStore()),
                             home: home.path, keys: TestRuleKey())
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    private func write(_ relative: String, bytes: Int) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    private func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(relative).path)
    }

    /// Every path under `root`, relative and sorted — the only description of a
    /// folder that a race cannot satisfy by accident.
    private func tree() -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }

    private func folder(_ rules: [Rule], depth: Int = 1) -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true, rules: rules, depth: depth)
    }

    private func rule(_ id: String, _ conditions: [RuleCondition], _ action: RuleAction) -> Rule {
        Rule(id: id, name: id, enabled: true, match: .all, conditions: conditions, action: action)
    }

    // MARK: - The plan and the path it refers to

    /// The one that loses somebody's file.
    ///
    /// A watched folder at depth 2 offers its rules the files in its subfolders,
    /// and each of those facts carries only a last path component. The sweep
    /// then rebuilds the path as `folder + name`, which for a file one level
    /// down names a *different* file — the one at the top level with the same
    /// name, if there is one.
    ///
    /// So the rule below ("larger than 2 MB → trash") is decided against the
    /// 3 MB `sub/big.bin` and executed against the 10-byte `big.bin`, which no
    /// rule matched and which the dry run never mentioned. Same names on two
    /// levels is not exotic: `sub/` here stands for any `Screenshots/`,
    /// `Invoices/2025/`, or the very subfolder a sort rule made a sweep ago.
    func testASweepBelowTheTopLevelActsOnTheFileItPlanned() throws {
        try write("big.bin", bytes: 10)
        try write("sub/big.bin", bytes: 3_000_000)

        let watched = folder([rule("r", [.size(.largerThan, megabytes: 2)], .trash)], depth: 2)
        let planned = engine.preview(watched)
        XCTAssertEqual(planned.count, 1, "only the 3 MB file is over the limit")

        engine.sweep(watched)

        XCTAssertTrue(exists("big.bin"),
                      "the 10-byte file no rule matched was acted on instead")
        XCTAssertFalse(exists("sub/big.bin"),
                       "the file the rule actually matched was never touched")
    }

    /// The same join with nothing to collide with, which is the ordinary case:
    /// a file one level down is looked for at `folder + name`, is not there, and
    /// the sweep reports it `missing`. So a watched folder set to any depth
    /// above 1 runs no rules at all below its top level, while the dry run beside
    /// the switch promises that it will.
    func testARuleReachesTheFilesTheDryRunPromised() throws {
        try write("sub/report.pdf", bytes: 8)

        let watched = folder([rule("r", [.fileExtension(["pdf"])], .addTag("seen"))], depth: 2)
        XCTAssertEqual(engine.preview(watched).map(\.facts.name), ["report.pdf"],
                       "the dry run promised one action")

        let report = engine.sweep(watched)

        XCTAssertEqual(report.acted, 1, "the dry run promised an action that never happened")
    }

    // MARK: - Twice

    /// Guarantee 3, stated as the only thing that can actually be observed: a
    /// sweep run twice over an unchanged folder leaves it exactly as the first
    /// one did.
    ///
    /// A rename whose result collides is where this breaks. `free(_:)` numbers
    /// the arriving file — `a.pdf` becomes `b 2.pdf` when `b.pdf` is taken — but
    /// `run` stamps `b.pdf`, the name the *pattern* produced. So the file that
    /// moved carries no mark, the next sweep renames it again to `b 3.pdf`, and
    /// the folder grows a file an hour, forever.
    func testASecondSweepOverAnUnchangedFolderChangesNothing() throws {
        try write("a.pdf", bytes: 4)
        try write("b.pdf", bytes: 99)

        let watched = folder([rule("r", [.fileExtension(["pdf"])], .rename(pattern: "b"))])
        engine.sweep(watched)
        let settled = tree()

        engine.sweep(watched)

        XCTAssertEqual(tree(), settled,
                       "a second sweep acted again on a file the first one had already renamed")
    }

    /// The same invariant for the action that already works, so a fix to the
    /// rename path cannot quietly break the move path on its way past.
    ///
    /// Green for a reason it does not name, and worth saying out loud: at depth
    /// 1 the sorted file sits at enumerator level 2 and the second sweep never
    /// reads it. Delete the `RuleStamp.isStamped` guard from `RuleRunner.run`
    /// and this still passes; so does breaking the sort's own idempotence. The
    /// two below are the ones that mean it.
    ///
    /// The tests that do fail without the stamp are the tagging one and the
    /// renaming one — `testASecondSweepAddsNothingBecauseNothingHappened` and
    /// `testASecondSweepOverAnUnchangedFolderChangesNothing`. Sorting no longer
    /// needs it, which is the point of the bucket check rather than a gap.
    func testASecondSweepDoesNotMoveAgain() throws {
        try write("a.pdf", bytes: 4)
        try write("b.pdf", bytes: 4)

        let watched = folder([rule("r", [.fileExtension(["pdf"])],
                                   .sortIntoSubfolder(.kind))],
                             depth: 1)
        engine.sweep(watched)
        let settled = tree()

        engine.sweep(watched)

        XCTAssertEqual(tree(), settled, "the sorted files were sorted a second time")
    }

    /// The same sweep at a depth that can see what the first one produced.
    ///
    /// A folder set to include its subfolders is the ordinary setting for a
    /// Downloads folder, and it is the only depth at which a sorting rule ever
    /// meets the file it sorted. Which of the two guards keeps it still is
    /// deliberately not asserted here — the stamp and the bucket check both
    /// answer, and the invariant is that the folder is unchanged.
    func testASecondSweepDoesNotMoveAgainWhereItCanSeeTheResult() throws {
        try write("a.pdf", bytes: 4)
        try write("b.pdf", bytes: 4)

        let watched = folder([rule("r", [.fileExtension(["pdf"])],
                                   .sortIntoSubfolder(.kind))],
                             depth: 8)
        engine.sweep(watched)
        let settled = tree()
        XCTAssertEqual(settled, ["Documents", "Documents/a.pdf", "Documents/b.pdf"],
                       "the premise: the second sweep will read these")

        engine.sweep(watched)

        XCTAssertEqual(tree(), settled, "the sorted files were sorted a second time")
    }

    /// And the same again with the mark taken off, which is what every sweep
    /// looks like on a volume that will not hold one.
    ///
    /// `RuleRunner.note` logs a stamp that would not stick and acts anyway,
    /// because refusing the file would make a volume without extended
    /// attributes a volume where no rule works. The sentence that makes that
    /// survivable is that the action is idempotent on an unchanged file — so
    /// this is that sentence, tested. Reachable wherever the attribute does not
    /// survive: a filesystem that refuses it, or an AppleDouble `._name`
    /// sidecar dropped in transit, on the `/Volumes` `WatchScope` admits on
    /// purpose. (Not exFAT, which this used to name: it keeps the stamp —
    /// ARCHITECTURE.md § Autopilot.)
    func testAnUnstampableVolumeDoesNotBuryTheFileDeeperEverySweep() throws {
        try write("a.pdf", bytes: 4)

        let watched = folder([rule("r", [.fileExtension(["pdf"])],
                                   .sortIntoSubfolder(.kind))],
                             depth: 8)
        engine.sweep(watched)
        let settled = tree()
        XCTAssertEqual(settled, ["Documents", "Documents/a.pdf"])

        unstamp()
        engine.sweep(watched)

        XCTAssertEqual(tree(), settled,
                       "the file was buried one folder deeper, and would be again every hour")
    }

    /// Every mark under `root`, removed. The rest of the folder is left exactly
    /// as the sweep left it, so the only thing the next sweep is missing is the
    /// record — which is the state an unstampable volume is in permanently.
    private func unstamp() {
        for relative in tree() {
            removexattr(root.appendingPathComponent(relative).path,
                        RuleStamp.attribute, XATTR_NOFOLLOW)
        }
    }

    // MARK: - Depth

    /// `WatchedFolder.depth` is an `Int` with nothing stopping it being 0 or
    /// negative — a settings field, a migration, a hand-edited plist. The safe
    /// direction is nothing: a folder read at depth 0 must not fall back to
    /// reading everything.
    func testANonsenseDepthReadsNothingRatherThanEverything() throws {
        try write("a.pdf", bytes: 4)
        try write("sub/b.pdf", bytes: 4)

        let rules = [rule("r", [.fileExtension(["pdf"])], .trash)]
        XCTAssertTrue(engine.preview(folder(rules, depth: 0)).isEmpty)
        XCTAssertTrue(engine.preview(folder(rules, depth: -1)).isEmpty)
        XCTAssertTrue(engine.preview(folder(rules, depth: Int.min)).isEmpty)
    }

    /// And the other end: nothing about a very large depth may turn into a crash
    /// or a walk that never returns. The tree is three levels deep, so any depth
    /// past three is the same answer.
    func testAnEnormousDepthIsJustTheWholeTree() throws {
        try write("one/two/three/c.pdf", bytes: 4)

        let rules = [rule("r", [.fileExtension(["pdf"])], .addTag("t"))]
        XCTAssertEqual(engine.preview(folder(rules, depth: 4)).map(\.facts.name), ["c.pdf"])
        XCTAssertEqual(engine.preview(folder(rules, depth: Int.max)).map(\.facts.name), ["c.pdf"])
    }

    // MARK: - Saving

    /// `AutopilotEngine.folders`'s setter encodes with `try?` and returns on
    /// failure, so anything JSON will not take discards the whole list — every
    /// folder and every rule — without a word to anyone.
    ///
    /// A non-finite `Double` is the reachable case: `ConditionRow.numberField`
    /// accepts any string `Double.init` parses and that is greater than zero,
    /// and `Double("1e999")` is `+∞`. One typo in a size field and the rules of
    /// every *other* watched folder stop being saved.
    func testSavingAFolderDoesNotSilentlyDiscardTheList() {
        let kept = WatchedFolder(id: "kept", path: "/Users/x/Downloads", rules: [
            rule("g", [.fileExtension(["pdf"])], .addTag("t")),
        ])
        engine.folders = [kept]
        XCTAssertEqual(engine.folders.map(\.id), ["kept"])

        // Reachability, not a contrivance: this is exactly what the size field
        // hands to the condition when someone types it.
        let typed = Double("1e999".replacingOccurrences(of: ",", with: "."))
        XCTAssertEqual(typed, .infinity, "the size field parses this and accepts it, being > 0")

        let typo = WatchedFolder(id: "typo", path: "/Users/x/Desktop", rules: [
            rule("b", [.size(.largerThan, megabytes: typed ?? .infinity)], .trash),
        ])
        engine.folders = [kept, typo]

        XCTAssertEqual(engine.folders.map(\.id), ["kept", "typo"],
                       "the assignment was a silent no-op and the caller has no way to know")
    }
}

/// Autopilot is the one module that acts with nobody watching, and until now it
/// left no record a person could read: the log carries counts and redacted
/// paths, which answers "did anything happen" and never "what happened to my
/// file". These are about the record, over a real sweep, because a history that
/// is only tested against a fabricated outcome is a history of the test.
extension AutopilotSweepTests {

    func testASweepWritesDownWhatItDid() throws {
        try write("report.pdf", bytes: 8)
        let watched = folder([rule("Tag PDFs", [.fileExtension(["pdf"])], .addTag("seen"))], depth: 1)

        XCTAssertTrue(engine.history.isEmpty, "nothing has happened yet")
        engine.sweep(watched)

        XCTAssertEqual(engine.history.map(\.file), ["report.pdf"])
        XCTAssertEqual(engine.history.first?.kind, .tagged)
        XCTAssertEqual(engine.history.first?.detail, "seen")
        XCTAssertEqual(engine.history.first?.rule, "Tag PDFs",
                       "the rule's name is the one word that says why")
    }

    /// The second sweep finds the same file already dealt with. A record then
    /// would be Autopilot reporting work it did not do, every time the timer
    /// fires, until the real history is buried under it.
    func testASecondSweepAddsNothingBecauseNothingHappened() throws {
        try write("report.pdf", bytes: 8)
        let watched = folder([rule("Tag PDFs", [.fileExtension(["pdf"])], .addTag("seen"))], depth: 1)

        engine.sweep(watched)
        let afterFirst = engine.history.count
        engine.sweep(watched)

        XCTAssertEqual(engine.history.count, afterFirst)
    }

    func testAFileThatWasMovedSaysWhereItWent() throws {
        try write("march.pdf", bytes: 8)
        let destination = home.appendingPathComponent("Invoices")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let watched = folder([rule("Invoices", [.fileExtension(["pdf"])],
                                   .move(to: destination.path))], depth: 1)

        engine.sweep(watched)

        XCTAssertEqual(engine.history.first?.kind, .moved)
        XCTAssertEqual(engine.history.first?.detail, "Invoices",
                       "the folder it landed in — a report, not a full path")
    }

    func testTheHistoryCanBeThrownAway() throws {
        try write("report.pdf", bytes: 8)
        engine.sweep(folder([rule("Tag PDFs", [.fileExtension(["pdf"])], .addTag("seen"))], depth: 1))
        XCTAssertFalse(engine.history.isEmpty)

        engine.clearHistory()

        XCTAssertTrue(engine.history.isEmpty)
    }
}
