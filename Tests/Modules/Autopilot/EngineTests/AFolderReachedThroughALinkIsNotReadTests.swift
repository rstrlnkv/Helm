import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// A watched folder whose *ancestor* became a link into `~/Library`.
///
/// The rules are stored in a property list any process running as the user can
/// write, and the folder is read before the runner is asked about any file in it.
/// The runner's per-file gate refuses what it is shown, but by then the folder
/// had been read without a gate and each refused file had been written into the
/// history — name and full path — in the same property list, which a process
/// with no Full Disk Access reads freely. So the file names of a protected
/// folder went to a place anybody could read, without any move happening.
///
/// The shape is the one the security pass probed: `~/Stuff` is a link to
/// `~/Library`, the watched folder is `~/Stuff/Inbox`, and `~/Library/Inbox`
/// is a real folder holding a file. Everything is real: a scratch home, a real
/// link, real files.
final class AFolderReachedThroughALinkIsNotReadTests: XCTestCase {

    private var home: URL!
    private var backing: InMemoryKeyValueStore!
    private var engine: AutopilotEngine!
    private var hijacked: WatchedFolder!
    private var honest: WatchedFolder!
    /// A name nothing else in the tree has, so finding it in the stored bytes
    /// can only mean it was written there.
    private let secret = "tax-return-2026.pdf"

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        let fm = FileManager.default
        let library = home.appendingPathComponent("Library")
        try write("Inbox/\(secret)", in: library)
        try fm.createSymbolicLink(at: home.appendingPathComponent("Stuff"),
                                  withDestinationURL: library)
        try write("Real/Inbox/notes.pdf", in: home)
        func watch(_ id: String, _ path: String) -> WatchedFolder {
            WatchedFolder(id: id, path: path, enabled: true, rules: [
                Rule(id: "r", name: "Sort", enabled: true, conditions: [.fileExtension(["pdf"])],
                     action: .move(to: home.appendingPathComponent("Sorted").path)),
            ], depth: 1)
        }
        hijacked = watch("hijacked", home.appendingPathComponent("Stuff/Inbox").path)
        honest = watch("honest", home.appendingPathComponent("Real/Inbox").path)
        backing = InMemoryKeyValueStore()
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)", backing: backing),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
        engine.folders = [hijacked, honest]
    }

    /// Everything the module wrote under its namespace, as text — the thing a
    /// process with no grant can read.
    private func storedText() -> String {
        let data = engine.history.compactMap { try? JSONEncoder().encode($0) }
        return data.compactMap { String(data: $0, encoding: .utf8) }.joined()
    }

    private var secretIsStillThere: Bool {
        FileManager.default.fileExists(atPath:
            home.appendingPathComponent("Library/Inbox/\(secret)").path)
    }

    func testTheSweepRefusesTheFolderAndReadsNothing() {
        let honestReport = engine.sweep(honest)
        XCTAssertEqual(honestReport.examined, 1, "control: the same shape without a link is read")

        let report = engine.sweep(hijacked)

        XCTAssertEqual(report.examined, 0, "the folder behind the link was read")
        XCTAssertEqual(report.folder, .refused)
        XCTAssertTrue(secretIsStillThere)
    }

    func testTheHourlySweepWritesNoNameOfTheProtectedFolderIntoTheHistory() {
        let reports = engine.sweepAll()

        XCTAssertEqual(reports.first { $0.folderID == "honest" }?.examined, 1,
                       "precondition: the sweep ran")
        XCTAssertEqual(reports.first { $0.folderID == "hijacked" }?.examined, 0)
        XCTAssertFalse(storedText().contains(secret), storedText())
        XCTAssertFalse(storedText().contains("Library"), storedText())
    }

    func testTheDryRunShowsNothingOfTheFolderBehindTheLink() {
        XCTAssertEqual(engine.preview(honest).count, 1, "control: a real folder previews")

        XCTAssertEqual(engine.preview(hijacked), [])
    }

    /// The other unattended leg is asked about a file behind the link. The gate
    /// is the first question `plan(for:)` asks, so the file is not planned and
    /// nothing is recorded for it at all — not a refusal, not its name. The
    /// ordinary file in the same batch is the proof the watcher ran.
    func testAWatcherEventBehindTheLinkRecordsNothingAndNoName() {
        let path = home.appendingPathComponent("Stuff/Inbox/\(secret)").path
        let ordinary = home.appendingPathComponent("Real/Inbox/notes.pdf").path
        engine.handle([path, ordinary])
        _ = engine.historyRefused   // the queue has drained once this returns

        let records = engine.history
        XCTAssertEqual(records.map(\.kind), [.moved], "precondition: the ordinary file was acted on")
        XCTAssertFalse(storedText().contains(secret), storedText())
        XCTAssertTrue(secretIsStillThere)
    }

    func testTheRecordOfAScopeRefusalCarriesNeitherNameNorPath() {
        let facts = FileFacts(name: secret, path: "/x/\(secret)", kind: .document, bytes: 1,
                              added: Date(), modified: Date(), now: Date())
        let plan = RulePlan(facts: facts, rule: Rule(id: "r", name: "Sort", enabled: true,
                                                     conditions: [], action: .trash))

        let scope = ActionRecord.of(plan, .refused(.outOfScope))
        let other = ActionRecord.of(plan, .refused(.missing))

        XCTAssertEqual(scope?.kind, .refused)
        XCTAssertEqual(scope?.file, "")
        XCTAssertEqual(scope?.path, "")
        XCTAssertEqual(other?.file, secret, "control: a refusal about the file itself keeps its name")
    }

    /// What the row shows instead of a file: the reason and the rule, once — two
    /// files refused for scope by one rule are one row, since a row naming
    /// neither could not tell them apart and would only repeat.
    func testTwoScopeRefusalsOfOneRuleAreOneRowWithNoSubject() throws {
        func refusal(_ path: String, at hour: Double) throws -> ActionRecord {
            let when = Date(timeIntervalSince1970: 1_784_116_800 + hour * 3_600)
            let facts = FileFacts(name: (path as NSString).lastPathComponent, path: path,
                                  kind: .document, bytes: 1, added: when, modified: when, now: when)
            let plan = RulePlan(facts: facts, rule: Rule(id: "r", name: "Sort", enabled: true,
                                                         conditions: [], action: .trash))
            return try XCTUnwrap(ActionRecord.of(plan, .refused(.outOfScope), at: when))
        }
        let first = try refusal("/x/a/report.pdf", at: 0), second = try refusal("/x/b/plan.pdf", at: 1)
        let now = second.at

        var history = ActionHistory.recording(first, into: [], now: now)
        history = ActionHistory.recording(second, into: history, now: now)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.file, "")
        XCTAssertEqual(history.first?.detail, RuleOutcome.Refusal.outOfScope.rawValue)
    }
}
