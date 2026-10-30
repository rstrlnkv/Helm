import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The engine's one unasked signal: a pass went into the history.
///
/// An unattended sweep writes the history with nobody pressing anything; the model
/// re-asks only because the engine says so, through the closure it was built with.
/// What the signal must keep is what the old event kept: said after the history
/// *landed* (a refused seal or an unwritable store is not a change anybody should
/// re-read for) and never for a return, whose only writer is the person's own
/// gesture and which reloads. Defect class kept: the model is told of a change
/// that did not happen, told twice, or never told.
///
/// Every absence has a control in the same class: the same engine built the same way
/// says it for a sweep that acted, so a silent closure cannot pass for «said nothing».
final class TheEngineSaysWhenAPassWentIntoTheHistoryTests: XCTestCase {

    private final class Said: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        func once() { lock.withLock { n += 1 } }
        var count: Int { lock.withLock { n } }
    }

    private var home: URL!
    private var root: URL!
    private var store: NamespacedStore!
    private var engine: AutopilotEngine!
    private let said = Said()

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                backing: InMemoryKeyValueStore())
        let said = self.said
        engine = AutopilotEngine(store: store, home: home.path,
                                 keys: TestRuleKey(), sequence: TestRuleSequence(),
                                 historyChanged: { said.once() })
    }

    private var sorting: WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true,
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])],
                                   action: .move(to: root.appendingPathComponent("Sorted").path))],
                      depth: 1)
    }

    func testASweepThatActedSaysSoOnce() throws {
        try write("a.pdf", in: root)
        try write("b.pdf", in: root)
        engine.sweep(sorting)
        XCTAssertEqual(engine.history.count, 2, "precondition: the sweep acted on both files")
        XCTAssertEqual(said.count, 1, "a pass of two records is one announcement")
    }

    func testASweepThatDidNothingSaysNothing() throws {
        try write("a.txt", in: root)
        // Control: the closure is wired, a sweep that acts speaks.
        try write("b.pdf", in: root)
        engine.sweep(sorting)
        XCTAssertEqual(said.count, 1, "control: a sweep that acted did not speak")

        engine.sweep(sorting)
        XCTAssertEqual(said.count, 1, "a sweep over a folder with nothing left to do said a pass was written")
    }

    func testAPassOverAHistorySomebodyElseWroteSaysNothing() throws {
        try write("a.pdf", in: root)
        engine.sweep(sorting)
        XCTAssertEqual(said.count, 1, "control: the first sweep spoke")
        store.set("00", for: RuleSeal.historyKey)

        try write("b.pdf", in: root)
        engine.sweep(sorting)

        XCTAssertEqual(engine.history.count, 1, "precondition: nothing was folded into the history that is not Helm's")
        XCTAssertEqual(said.count, 1, "an announcement for a write the seal refused")
    }

    /// The other refusal: the stored history is Helm's (here, none yet) but the key cannot
    /// seal what would be written, so nothing lands. The sweep still moved the file; the
    /// model must not be told to re-read a history that did not change.
    func testAPassTheSealCouldNotWriteSaysNothing() throws {
        let said = self.said
        let keyless = AutopilotEngine(store: store, home: home.path,
                                      keys: TestRuleKey(available: false), sequence: TestRuleSequence(),
                                      historyChanged: { said.once() })
        try write("a.pdf", in: root)

        keyless.sweep(sorting)

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Sorted/a.pdf").path),
                      "precondition: the sweep moved the file")
        XCTAssertTrue(keyless.history.isEmpty, "precondition: nothing was written to the history")
        XCTAssertEqual(said.count, 0, "an announcement for a write that never landed")
    }

    func testAReturnSaysNothing() async throws {
        try write("a.pdf", in: root)
        engine.sweep(sorting)
        XCTAssertEqual(said.count, 1, "control: the sweep spoke")
        let record = try XCTUnwrap(engine.history.first)

        let report = await engine.putBack(record: record.id)

        XCTAssertEqual(report.restored.count, 1, "precondition: the return really put the file back")
        XCTAssertEqual(said.count, 1, "a return was announced; the gesture reloads, and a second read is for nothing")
    }
}
