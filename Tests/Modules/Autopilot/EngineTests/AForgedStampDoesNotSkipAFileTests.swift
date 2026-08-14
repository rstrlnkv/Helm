import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The mark, from the point of view of the file wearing it.
///
/// `RuleStamp` is asked before anything happens, and a file it answers yes about
/// is skipped in silence — no action, no history row, nothing in the log. The
/// attribute it reads sits on somebody's file where any process running as the
/// user may write, and what it used to hold was the rule's id, which the same
/// process can read out of `com.helm.app.plist`. So a program that had just
/// landed in `~/Downloads` could immunise itself against the rule written to
/// catch it, and the only trace was the file still being there.
///
/// Every assertion here is a listing or a file's contents. "Acted on" counted by
/// a `SweepReport` field would be satisfied by the rule never having matched.
final class AForgedStampDoesNotSkipAFileTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder(_ rules: [Rule]) -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true, rules: rules, depth: 1)
    }

    private func movingPDFs(_ id: String = "rule-id-from-the-plist") -> WatchedFolder {
        folder([Rule(id: id, name: "Sort", enabled: true, match: .all,
                     conditions: [.fileExtension(["pdf"])],
                     action: .move(to: root.appendingPathComponent("Sorted").path))])
    }

    /// What the attribute holds, written the way anything on the machine can
    /// write it.
    private func plant(_ value: [String], on file: URL) throws {
        let data = try JSONEncoder().encode(value)
        let wrote = data.withUnsafeBytes {
            setxattr(file.path, RuleStamp.attribute, $0.baseAddress, $0.count, 0, XATTR_NOFOLLOW)
        }
        XCTAssertEqual(wrote, 0, "the premise: this file now carries a stamp")
    }

    private func stampValue(on file: URL) throws -> [String] {
        let length = getxattr(file.path, RuleStamp.attribute, nil, 0, 0, XATTR_NOFOLLOW)
        // Asserted and then guarded: a skip here would read as green in a
        // failures-only summary, and `Data(count:)` traps on the -1 that a file
        // with no attribute answers.
        XCTAssertGreaterThan(length, 0, "the premise: Helm stamped this file")
        guard length > 0 else { return [] }
        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes {
            getxattr(file.path, RuleStamp.attribute, $0.baseAddress, length, 0, XATTR_NOFOLLOW)
        }
        return try JSONDecoder().decode([String].self, from: data)
    }

    private func moved(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath:
            root.appendingPathComponent("Sorted/\(name)").path)
    }

    /// The measurement, as it was made: a file carrying the rule's own id was
    /// skipped and the ordinary file beside it was acted on.
    func testAStampAnybodyCouldWriteDoesNotStopTheRule() throws {
        let malware = try write("malware.pdf", in: root)
        try write("ordinary.pdf", in: root)
        try plant(["rule-id-from-the-plist"], on: malware)

        engine.sweep(movingPDFs())

        XCTAssertTrue(moved("ordinary.pdf"), "the rule did not run at all, so this proves nothing")
        XCTAssertTrue(moved("malware.pdf"), "a stamp anybody can write kept the rule off this file")
    }

    /// And the copy, which is the attack left standing if the mark were secret
    /// but not tied to the file: read the attribute off a file the rule has
    /// already had its turn at — no permission needed — and write it onto the
    /// one that wants immunity.
    func testAStampCopiedFromAnotherFileDoesNotStopTheRule() throws {
        try write("first.pdf", in: root)
        engine.sweep(movingPDFs())
        let landed = root.appendingPathComponent("Sorted/first.pdf")
        let real = try stampValue(on: landed)

        let malware = try write("malware.pdf", in: root)
        try plant(real, on: malware)
        engine.sweep(movingPDFs())

        XCTAssertTrue(moved("malware.pdf"), "a stamp copied off another file kept the rule off this one")
    }

    /// The control, and the reason the two above are not simply "the stamp stopped
    /// working". A mark Helm wrote is still a mark Helm honours: the rule does not
    /// get a second turn at the same file.
    func testTheMarkHelmWritesStillStopsASecondTurn() throws {
        let file = try write("a.pdf", in: root)
        let rule = Rule(id: "r", name: "r", enabled: true, match: .all,
                        conditions: [.fileExtension(["pdf"])], action: .addTag("seen"))
        let plan = RulePlan(facts: FileFacts(name: "a.pdf", path: file.path, kind: .document,
                                             bytes: 4, added: Date(), modified: Date()),
                            rule: rule)
        let runner = RuleRunner(home: home.path)

        XCTAssertEqual(runner.run(plan, at: file.path, key: TestRuleKey.material), .tagged("seen"))
        XCTAssertEqual(runner.run(plan, at: file.path, key: TestRuleKey.material), .alreadyDone,
                       "the rule took a second turn at a file it had already marked")
    }

    /// A stamp written before this build holds a rule id rather than a mark, and
    /// it is no longer honoured — the file gets one more turn from each rule that
    /// had already had one, and is marked properly on the way through. That is
    /// the direction this mechanism fails in by design: work redone, never work
    /// done twice to the same file.
    func testAStampFromAnOlderBuildIsRedoneRatherThanTrusted() throws {
        let file = try write("a.pdf", in: root)
        try plant(["rule-id-from-the-plist"], on: file)

        engine.sweep(movingPDFs())

        XCTAssertTrue(moved("a.pdf"))
        let marks = try stampValue(on: root.appendingPathComponent("Sorted/a.pdf"))
        XCTAssertTrue(marks.contains("rule-id-from-the-plist"),
                      "the older build's value was thrown away rather than left alone")
        XCTAssertEqual(marks.count, 2, "the file did not gain a mark of the new kind")
    }
}
