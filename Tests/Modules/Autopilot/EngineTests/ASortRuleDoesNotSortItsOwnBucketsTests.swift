import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// **A sorting rule was handed the folders it had made itself.**
///
/// From the owner's log: a rule sorting by kind puts every directory into
/// `Folders/`, and `Folders/` is a directory. Every hour the rule planned to
/// move `~/Downloads/Folders` inside itself, `RuleRunner.move` refused it
/// `outOfScope` — correctly, a folder cannot be moved into itself — and the
/// refusal was logged and written into the history again, forever. The gate was
/// right; the rule was aiming at its own bucket.
///
/// So a sorting rule does not count the buckets of its own scheme as items. Not
/// a refusal: a refusal is a thing that was going to happen and could not, and
/// this was never going to happen. It is decided in `RulePlan`, the one value
/// the dry run shows and the runner executes, so both agree without being asked
/// to.
final class ASortRuleDoesNotSortItsOwnBucketsTests: XCTestCase {

    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private func facts(_ name: String, isDirectory: Bool = true,
                       kind: FileKind? = nil) -> FileFacts {
        FileFacts(name: name, path: "/Users/x/Downloads/" + name,
                  kind: kind ?? (isDirectory ? .folder : .document), bytes: 4,
                  added: day, modified: day, isDirectory: isDirectory, now: day)
    }

    private func sorting(_ scheme: SortScheme, named name: String) -> Rule {
        Rule(id: "sort", name: "sort", enabled: true, match: .all,
             conditions: [.name(.is, name)], action: .sortIntoSubfolder(scheme))
    }

    // MARK: - The item that is a bucket

    func testTheBucketOfTheRulesOwnSchemeIsNotAnItem() {
        let plan = RulePlan.decide(facts("Folders"),
                                   rules: [sorting(.kind, named: "Folders")])

        XCTAssertNil(plan, "the rule planned to move its own bucket inside itself")
    }

    /// Every bucket the scheme owns, not only the one this directory would be
    /// put in. `Images/` holds what the same rule sorted there; moving it into
    /// `Folders/Images` is the rule tearing up its own filing.
    ///
    /// The names come from `SortBucket` rather than from a list written here,
    /// so a bucket renamed on one side cannot pass this on the other.
    func testEveryBucketOfTheSchemeIsSkipped() {
        for kind in FileKind.allCases {
            let bucket = SortBucket.name(for: facts("x", isDirectory: false, kind: kind),
                                         scheme: .kind)

            XCTAssertNil(RulePlan.decide(facts(bucket),
                                         rules: [sorting(.kind, named: bucket)]),
                         "\(bucket) is a bucket of the rule's own scheme")
        }
    }

    func testAMonthFolderIsTheBucketOfAMonthRule() {
        XCTAssertNil(RulePlan.decide(facts("2026-07"),
                                     rules: [sorting(.month, named: "2026-07")]))
    }

    // MARK: - What is still an item

    /// A file called `Folders` is a file. The skip is about a directory a sort
    /// rule would be filing into itself, and nothing else.
    func testAFileNamedLikeABucketIsAnOrdinaryItem() {
        let plan = RulePlan.decide(facts("Folders", isDirectory: false),
                                   rules: [sorting(.kind, named: "Folders")])

        XCTAssertEqual(plan?.rule.id, "sort")
    }

    /// A bucket of the *other* scheme is somebody's folder as far as this rule
    /// is concerned, and moving it is honest work: a `.kind` rule files
    /// `2026-07/` under `Folders/` and a `.month` rule files `Images/` under
    /// this month.
    func testABucketOfAnotherSchemeIsAnOrdinaryItem() {
        XCTAssertEqual(RulePlan.decide(facts("2026-07"),
                                       rules: [sorting(.kind, named: "2026-07")])?.rule.id,
                       "sort")
        XCTAssertEqual(RulePlan.decide(facts("Images"),
                                       rules: [sorting(.month, named: "Images")])?.rule.id,
                       "sort")
    }

    /// `2026-13` is not a name the scheme can produce, so it is not its bucket.
    func testAMonthThatDoesNotExistIsAnOrdinaryFolder() {
        XCTAssertEqual(RulePlan.decide(facts("2026-13"),
                                       rules: [sorting(.month, named: "2026-13")])?.rule.id,
                       "sort")
    }

    /// The skip steps aside the way a disabled rule does: the rule below gets
    /// its turn at the directory, because a bucket is not an item *of this
    /// rule* rather than not an item at all.
    func testTheRuleBelowGetsItsTurnAtTheBucket() {
        let rules = [sorting(.kind, named: "Folders"),
                     Rule(id: "tag", name: "tag", enabled: true, match: .all,
                          conditions: [.name(.is, "Folders")], action: .addTag("seen"))]

        XCTAssertEqual(RulePlan.decide(facts("Folders"), rules: rules)?.rule.id, "tag")
    }
}

/// The same thing over a real folder, because the refusal in the owner's log
/// was a whole sweep's — and because the dry run and the sweep read one value,
/// which is only worth saying if something asks them both.
final class ASweepDoesNotOfferItsOwnBucketTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func tree() -> [String] {
        let all = FileManager.default.enumerator(atPath: root.path)?.allObjects as? [String]
        return (all ?? []).sorted()
    }

    /// Every directory into `Folders/` — the rule from the log.
    private func watched() -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true, rules: [
            Rule(id: "r", name: "Folders", enabled: true, match: .all,
                 conditions: [.kind(.folder)], action: .sortIntoSubfolder(.kind)),
        ], depth: 1)
    }

    func testTheDryRunDoesNotShowTheBucket() throws {
        try write("Folders/old.pdf", in: root, bytes: 4)
        try write("Notes/a.pdf", in: root, bytes: 4)

        let planned = engine.preview(watched()).map(\.facts.name)

        XCTAssertEqual(planned, ["Notes"], "the dry run promised to move the bucket into itself")
    }

    func testASweepRefusesNothingAndLeavesTheBucketWhereItIs() throws {
        try write("Folders/old.pdf", in: root, bytes: 4)
        try write("Notes/a.pdf", in: root, bytes: 4)

        let report = engine.sweep(watched())

        XCTAssertEqual(report.refused, 0, "the bucket was refused, hourly and forever")
        XCTAssertEqual(tree(), ["Folders", "Folders/Notes", "Folders/Notes/a.pdf",
                                "Folders/old.pdf"])
    }

    /// And nothing is written down about it: the thirty-day history is where a
    /// person looks to see what Autopilot did, and an hourly refusal of a
    /// folder nobody asked to move buries it.
    ///
    /// The move is asserted beside the absence on purpose — "no refusal in the
    /// history" is true of a sweep that never ran.
    func testTheHistoryHoldsTheMoveAndNoRefusal() throws {
        try write("Folders/old.pdf", in: root, bytes: 4)
        try write("Notes/a.pdf", in: root, bytes: 4)

        engine.sweep(watched())

        XCTAssertEqual(engine.history.map { [$0.file, $0.kind.rawValue, $0.detail] },
                       [["Notes", "moved", "Folders"]],
                       "the bucket was written into the history, hourly and forever")
    }
}
