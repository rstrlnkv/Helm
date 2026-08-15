import Foundation
import XCTest
import HelmContract
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The engine acts on a timer and on files arriving — with the page open and
/// nobody pressing anything. Until the `history` event existed, the open page
/// read the history once and then drew an hour of unattended work as nothing.
///
/// The announcement carries no data on purpose, and it must be as honest as the
/// write it follows: a history that was *not* written — refused by the seal, or
/// a pass with nothing in it — is a history that must not be announced, because
/// the page would re-read and re-draw the same nothing.
///
/// Every absence below is pinned with a marker event: `LocalTransport` replays
/// past events to a new subscriber in the order they were first emitted, so
/// "the marker came first" is a deterministic way to say "no history event was
/// emitted before it" — no timeout, nothing for a scheduler to satisfy.
final class AHistoryChangeIsAnnouncedTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var store: NamespacedStore!
    private var transport: LocalTransport!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                backing: InMemoryKeyValueStore())
        transport = LocalTransport()
        engine = AutopilotEngine(store: store, transport: transport, home: home.path,
                                 keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder() -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true,
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])],
                                   action: .move(to: root.appendingPathComponent("Sorted").path))],
                      depth: 1)
    }

    private func marker(_ name: String) {
        transport.emit(EngineEvent(name: name, payload: Data()))
    }

    private func nextEvent() async -> EngineEvent? {
        var events = transport.events.makeAsyncIterator()
        return await events.next()
    }

    func testASweepThatRecordedSomethingAnnouncesTheHistory() async throws {
        try write("a.pdf", in: root)
        engine.sweep(folder())
        XCTAssertFalse(engine.history.isEmpty, "nothing was recorded, so this proves nothing")
        marker("test.marker")

        let first = await nextEvent()

        XCTAssertEqual(first?.name, AutopilotEvent.history.rawValue,
                       "the history changed and nothing said so")
    }

    /// A sweep with nothing to do writes nothing, so it announces nothing: the
    /// hourly timer fires whether or not anything happened, and an event per
    /// empty pass would have every open page re-reading an unchanged store.
    func testASweepWithNothingToRecordAnnouncesNothing() async throws {
        engine.sweep(folder())
        XCTAssertTrue(engine.history.isEmpty)
        marker("test.marker")

        let first = await nextEvent()

        XCTAssertEqual(first?.name, "test.marker",
                       "an empty sweep announced a history that did not change")
    }

    /// A forged history refuses the record, and the announcement goes with it —
    /// an event over a refused write would send the page to re-read a store the
    /// engine just declined to touch.
    ///
    /// Subscribed *live* before the refused sweep: the replay keeps one event
    /// per name, so it cannot tell an honest pass's announcement from a forged
    /// one made later under the same name.
    func testAForgedHistoryRefusesTheAnnouncementWithTheRecord() async throws {
        try write("a.pdf", in: root)
        engine.sweep(folder())
        XCTAssertFalse(engine.history.isEmpty)
        marker("test.before")
        var events = transport.events.makeAsyncIterator()
        // Consuming the marker proves the subscription is registered; whatever
        // arrives after it arrived live. Never blocks — the marker is there in
        // every state of the emit under test.
        while let event = await events.next(), event.name != "test.before" {}
        store.set("00", for: RuleSeal.historyKey)

        let before = try write("b.pdf", in: root)
        engine.sweep(folder())
        XCTAssertFalse(FileManager.default.fileExists(atPath: before.path),
                       "the rule did not act, so the refused remember was never reached")
        marker("test.after")

        let next = await events.next()
        XCTAssertEqual(next?.name, "test.after",
                       "a refused write was announced as a change")
    }

    /// The seal can fail on its own — a keychain that will not answer — and a
    /// history that was not signed was not written. The announcement follows
    /// the write, not the intention to write.
    func testAHistoryTheSealCouldNotSignIsNotAnnounced() async throws {
        let deaf = AutopilotEngine(store: store, transport: transport, home: home.path,
                                   keys: TestRuleKey(available: false),
                                   sequence: TestRuleSequence())
        try write("a.pdf", in: root)

        let report = deaf.sweep(folder())

        XCTAssertGreaterThan(report.acted + report.refused + report.failed, 0,
                             "the sweep produced no records, so the write was never tried")
        XCTAssertTrue(deaf.history.isEmpty, "an unsigned history was written anyway")
        marker("test.marker")
        let first = await nextEvent()
        XCTAssertEqual(first?.name, "test.marker",
                       "a write the seal refused was announced as a change")
    }
}
