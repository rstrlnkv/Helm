import Foundation
import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Autopilot_Engine

/// What a scope refusal leaves in `helm.log`, and what the sweep reads before
/// the runner is ever asked.
///
/// The history already writes neither the name nor the path of a file refused
/// for lying outside the allowed folders (`AFolderReachedThroughALinkIsNotReadTests`).
/// The log is the same kind of place — readable by any process running as the
/// user, with no grant — and the sweep's and the watcher's warning lines named
/// the file there all the same: `refused <path>: outOfScope`, the leaf in clear.
/// Reachable by a link put in place of an ancestor between the root check and
/// the walk.
///
/// And the second half of the same window: what the walk *returns* is filtered
/// by the same gate the runner would apply, so a file the gate refuses is never
/// planned, never counted as refused and never written anywhere.
final class AScopeRefusalNamesNothingInTheLogTests: XCTestCase {

    private var home: URL!
    private var engine: AutopilotEngine!
    private let secret = "passport-scan-2026.pdf"

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        try write("Library/Inbox/\(secret)", in: home)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Stuff"),
            withDestinationURL: home.appendingPathComponent("Library"))
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func watch(_ path: String) -> WatchedFolder {
        WatchedFolder(id: "w", path: path, enabled: true, rules: [
            Rule(id: "r", name: "Sort", enabled: true, conditions: [.fileExtension(["pdf"])],
                 action: .move(to: home.appendingPathComponent("Sorted").path)),
        ], depth: 1)
    }

    private func logged() -> [String] {
        HelmLog.shared.recentEntries().filter { $0.category == AutopilotEngine.moduleID }.map(\.message)
    }

    /// The line a runner refusal for scope writes — the one a file that vanishes
    /// or is swapped between the plan and the run still reaches — names the rule
    /// and not the file.
    func testARefusalForScopeLogsNoLeaf() {
        let now = Date()
        let facts = FileFacts(name: secret, path: "/x/\(secret)", kind: .document, bytes: 1,
                              added: now, modified: now, now: now)
        let plan = RulePlan(facts: facts, rule: Rule(id: "r", name: "Sort", enabled: true,
                                                     conditions: [], action: .trash))

        let scope = AutopilotEngine.refusalLine(.outOfScope, plan: plan, path: facts.path)
        let other = AutopilotEngine.refusalLine(.missing, plan: plan, path: facts.path)

        XCTAssertFalse(scope.contains(secret), scope)
        XCTAssertTrue(scope.contains("rule r") && scope.contains("outOfScope"), scope)
        XCTAssertTrue(other.contains("refused"), "control: the other reasons are still a line — \(other)")
    }

    /// The watcher is told about a file behind a link into `~/Library`: it is
    /// dropped before it is planned, so no line about it is written — and the
    /// ordinary file in the same batch, which is what shows the watcher ran,
    /// does not name the protected one either.
    func testAWatcherEventBehindTheLinkLogsNothingAboutIt() throws {
        HelmLog.shared.setEnabled(true)
        defer { HelmLog.shared.setEnabled(false); HelmLog.shared.clearTail() }
        HelmLog.shared.clearTail()
        try write("Real/Inbox/notes.pdf", in: home)
        engine.folders = [watch(home.appendingPathComponent("Stuff/Inbox").path),
                          watch(home.appendingPathComponent("Real/Inbox").path)]

        engine.handle([home.appendingPathComponent("Stuff/Inbox/\(secret)").path,
                       home.appendingPathComponent("Real/Inbox/notes.pdf").path])
        _ = engine.historyRefused   // the queue has drained once this returns

        let lines = logged()
        XCTAssertTrue(lines.contains { $0.contains("moved") },
                      "precondition: the watcher acted on the ordinary file — \(lines)")
        XCTAssertFalse(lines.contains { $0.contains(secret) || $0.contains("refused") }, "\(lines)")
    }

    /// A file that is a link out of the watched folder: the walk lists it under
    /// the folder's own spelling, the gate resolves it into `~/Library`. It is
    /// not offered to any rule — not previewed, not counted refused, not
    /// recorded.
    func testAFileTheGateRefusesIsNotReadAtAll() throws {
        try write("Downloads/mine.pdf", in: home)
        try FileManager.default.createSymbolicLink(
            at: home.appendingPathComponent("Downloads/looks-harmless.pdf"),
            withDestinationURL: home.appendingPathComponent("Library/Inbox/\(secret)"))
        let folder = watch(home.appendingPathComponent("Downloads").path)
        engine.folders = [folder]

        XCTAssertEqual(engine.preview(folder).map(\.facts.name), ["mine.pdf"],
                       "the dry run offered the file behind the link")
        let report = engine.sweep(folder)
        XCTAssertEqual(report.folder, .read, "precondition: the folder was read")
        XCTAssertEqual(report.acted, 1, "precondition: the ordinary file moved")
        XCTAssertEqual(report.refused, 0, "a file the gate refuses was counted and planned")
        XCTAssertEqual(report.examined, 1)
        XCTAssertEqual(engine.history.filter { $0.kind == .refused }.count, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: home.appendingPathComponent("Library/Inbox/\(secret)").path))
    }
}
