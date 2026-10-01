import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// **Records older than thirty days are never on the page, so there is nothing
/// there to clear.**
///
/// The history card is drawn only when it has a pass, a reason or a refusal to
/// show (`drawsHistory`), and an earlier pass asked whether a store holding
/// nothing but old records leaves the person with no way to clear them. It does
/// not, for a reason that lives in the engine rather than on the page: the
/// `history` reply is read through the thirty-day window on the way out, so the
/// page is handed an empty list for such a store and its «Clear» was never
/// offered for it — before the card was made conditional as well as after. The
/// old rows also leave the store itself: the next record written prunes by the
/// same window.
///
/// A fake that returned the store unfiltered is what made the question look
/// open. These hold the real engine's answer.
final class AStaleHistoryIsNeverHandedToThePageTests: XCTestCase {

    private var store: NamespacedStore!
    private var keys: TestRuleKey!
    private var engine: AutopilotEngine!
    private var home: URL!

    override func setUpWithError() throws {
        home = scratchDirectory("stale-history")
        keys = TestRuleKey()
        store = NamespacedStore(namespace: "autopilot.test.\(UUID().uuidString)",
                                backing: InMemoryKeyValueStore())
        engine = AutopilotEngine(store: store, home: home.path, keys: keys,
                                 sequence: TestRuleSequence())
    }

    private func record(daysAgo: Double, file: String) -> ActionRecord {
        ActionRecord(at: Date(timeIntervalSinceNow: -daysAgo * 86_400), rule: "Sort",
                     file: file, kind: .moved, detail: "Sorted",
                     path: home.path + "/" + file, destination: home.path + "/Sorted/" + file,
                     run: "old")
    }

    /// Helm's own signature over the records, written the way the engine writes
    /// them, so the store is one the engine accepts as its own.
    private func plant(_ records: [ActionRecord]) throws {
        let sealed = SealedRules(store: store, keys: keys, sequence: TestRuleSequence())
        let data = try XCTUnwrap(ActionHistory.encode(records))
        XCTAssertTrue(sealed.seal(history: data))
        store.set(data, for: ActionHistory.storeKey)
    }

    private func stored() -> [ActionRecord] {
        ActionHistory.decode(store.data(ActionHistory.storeKey))
    }

    func testAStoreOfOnlyOldRecordsReadsAsNothingToThePage() async throws {
        try plant([record(daysAgo: 40, file: "old.pdf")])
        XCTAssertEqual(stored().count, 1, "precondition: the store does hold the old record")
        XCTAssertFalse(engine.historyRefused, "precondition: it is Helm's own")

        XCTAssertEqual(engine.history, [])
        let command = EngineCommand(name: AutopilotCommand.history.rawValue)
        let reply = try await engine.transport.send(command)
        let handed = try JSONDecoder().decode([ActionRecord].self, from: reply)
        XCTAssertEqual(handed, [], "the page was handed a record older than the window")
    }

    func testTheNextRecordWrittenTakesTheOldRowsOutOfTheStore() throws {
        try plant([record(daysAgo: 40, file: "old.pdf")])
        let inbox = home.appendingPathComponent("Inbox")
        try write("new.pdf", in: inbox)
        let folder = WatchedFolder(id: "f", path: inbox.path, rules: [
            Rule(id: "r", name: "Sort", enabled: true, conditions: [.fileExtension(["pdf"])],
                 action: .move(to: home.appendingPathComponent("Sorted").path)),
        ], depth: 1)
        engine.folders = [folder]

        let report = engine.sweep(folder)

        XCTAssertEqual(report.acted, 1, "precondition: the sweep wrote a record")
        XCTAssertEqual(stored().map(\.file), ["new.pdf"], "the old row stayed in the store")
    }
}
