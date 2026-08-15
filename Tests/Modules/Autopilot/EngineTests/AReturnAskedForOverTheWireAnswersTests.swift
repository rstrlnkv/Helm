import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// «Put back» pressed on the page, over the wire the page actually uses.
///
/// **Every existing test of a return calls the engine directly**, from the
/// thread the test is on: `AHistoryNotHelmsPutsNothingBackTests` calls
/// `engine.undo(record.id)`, and the UI tests answer the command from a fake wire
/// that has no engine behind it. So the one arrangement the person's press
/// actually takes — transport → `answer(.undo,)` → `putBack(command:)` →
/// `offQueue` → `undo(_:)` — is the one arrangement nothing exercises, and the
/// two halves of it disagree about which thread they are on.
///
/// `offQueue` is `queue.async`, and `undo(_:)` opens with `queue.sync`. `queue` is
/// the serial `helm.rules`, so the second is called from a block already running
/// on it, and `DispatchQueue.sync` targeting the queue it is called from is
/// documented as deadlock rather than as reentrancy. What it costs is not one
/// button: `helm.rules` also carries the hourly sweep, the FSEvents batch, the
/// watch refresh and `clearHistory`, so the module stops doing anything at all
/// for the life of the process, having said nothing.
///
/// **Gated, and this is the one place in the suite where that is not a way of
/// avoiding a failure.** Measured 2026-08-15: sending `.undo` over the engine's
/// transport does not hang, it *traps* — `xctest` exits on signal 5 and the
/// triggered thread is `__DISPATCH_WAIT_FOR_QUEUE__` under `AutopilotEngine.undo`
/// under `offQueue`. A process that aborts takes every other case in this bundle
/// with it and reports them as nothing at all, which is worse than useless in a
/// failures-only summary. So the reproduction is behind `HELM_WIRE_UNDO=1`, and
/// the *gate* for the same defect is `TheQueueIsNotAskedToWaitForItselfTests`,
/// which reads the composition and fails without crashing. A skip alone would
/// read as green, which CLAUDE.md names as its own family of defect.
///
/// ```
/// HELM_WIRE_UNDO=1 swift test --filter AReturnAskedForOverTheWireAnswersTests
/// ```
///
/// **Running it that way leaves a directory behind, and there is no way not to.**
/// `scratchDirectory` reclaims in a teardown block, and a process that aborts
/// runs no teardown — so each gated run leaves one `helm-home-…` in `$TMPDIR`.
/// Said out loud rather than left to be discovered, since 7621 of those
/// accumulated once from teardowns that merely looked right:
/// `rm -rf "$TMPDIR"/helm-home-*` afterwards, or run it once and read the crash
/// report. This stops being true the day the defect is fixed.
///
/// Every case is written with a timeout rather than an `await` that would hang,
/// so that a fix which turns the trap into a wait is reported rather than waited
/// on — and each asserts first that the thing it is about really happened, since
/// a report that never arrives and a report that arrives empty are different
/// failures and must not read alike.
final class AReturnAskedForOverTheWireAnswersTests: XCTestCase {

    /// The gate. `XCTSkipUnless` at the head of each case rather than in
    /// `setUp`: a skip thrown from setup is reported against the setup and not
    /// against the behaviour, and the reason is the thing worth reading.
    private func onlyWhenAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_WIRE_UNDO"] == "1", """
            aborts the process: AutopilotEngine.undo takes queue.sync from inside a block \
            offQueue put on that same serial queue. The gate that fails without crashing is \
            TheQueueIsNotAskedToWaitForItselfTests; run this with HELM_WIRE_UNDO=1 to watch it.
            """)
    }

    private var home: URL!
    private var root: URL!
    private var store: NamespacedStore!
    private var engine: AutopilotEngine!

    /// Long enough that a slow machine is not the reason, short enough that a
    /// deadlocked queue is reported rather than waited on: the work behind one
    /// return is a single `moveItem` in a temporary folder.
    private let patience: TimeInterval = 10

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                backing: InMemoryKeyValueStore())
        engine = AutopilotEngine(store: store, home: home.path,
                                 keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder() -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true,
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])],
                                   action: .move(to: root.appendingPathComponent("Sorted").path))],
                      depth: 1)
    }

    /// A sweep that really moved something, asserted — a return of nothing would
    /// answer instantly and prove nothing about the thread it answered on.
    @discardableResult
    private func aSweptFile(_ name: String = "a.pdf") throws -> URL {
        let file = try write(name, in: root)
        engine.sweep(folder())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "nothing was moved, so this proves nothing")
        return file
    }

    /// One command over the engine's own transport, with a clock on it.
    ///
    /// Nil is «it never answered», which is the state this file exists for and
    /// which no `await` could report — an `await` on a deadlocked queue simply
    /// never returns, and the suite hangs instead of failing.
    private func ask(_ command: AutopilotCommand, id: String) async -> Data? {
        let answered = expectation(description: "\(command.rawValue) answered")
        let box = Box()
        let transport = engine.transport
        let payload = EngineReply.encode(UndoRequest(id: id),
                                         for: EngineCommand(name: command.rawValue))
        Task {
            box.data = try? await transport.send(EngineCommand(name: command.rawValue,
                                                               payload: payload))
            answered.fulfill()
        }
        await fulfillment(of: [answered], timeout: patience)
        return box.data
    }

    /// The reply, from the task that received it. A class rather than a captured
    /// `var`: the task outlives the wait when the wait times out, and a struct
    /// written from it would be a data race the moment this file reported the
    /// defect it is here to report.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Data?
        var data: Data? {
            get { lock.withLock { stored } }
            set { lock.withLock { stored = newValue } }
        }
    }

    // MARK: - One record

    func testAReturnAskedForOverTheWireAnswers() async throws {
        try onlyWhenAsked()
        let file = try aSweptFile()
        let record = try XCTUnwrap(engine.history.first)

        let reply = await ask(.undo, id: record.id)

        let data = try XCTUnwrap(reply, """
            the undo command never answered: the handler dispatches onto helm.rules and then \
            calls queue.sync on it from inside, which deadlocks the queue the sweep, the \
            watcher and Clear all run on
            """)
        let report = try XCTUnwrap(try? JSONDecoder().decode(UndoReport.self, from: data),
                                   "the reply came back as \(data.count) bytes of nothing")
        XCTAssertEqual(report.restored.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "the report said the file went back and it did not")
    }

    /// The whole-pass gesture goes through the same handler, so it is the same
    /// question — asked separately because the two arms are two lines and only
    /// one of them has to be wrong.
    func testAWholePassAskedForOverTheWireAnswers() async throws {
        try onlyWhenAsked()
        try write("a.pdf", in: root)
        try write("b.pdf", in: root)
        engine.sweep(folder())
        let run = try XCTUnwrap(engine.history.first?.run)
        XCTAssertEqual(engine.history.count, 2, "the pass this test puts back is not two files")

        let reply = await ask(.undoRun, id: run)

        let data = try XCTUnwrap(reply, "the undoRun command never answered")
        let report = try XCTUnwrap(try? JSONDecoder().decode(UndoReport.self, from: data))
        XCTAssertEqual(report.restored.count, 2)
    }

    // MARK: - And what it costs the rest of the module

    /// A queue that has stopped is not a button that did nothing. `helm.rules`
    /// carries the hourly sweep as well, and `Run now` goes onto it by the same
    /// `offQueue` — so this asks the module to do its ordinary work *after* a
    /// return has been requested over the wire.
    func testTheModuleStillWorksAfterAReturnHasBeenAskedFor() async throws {
        try onlyWhenAsked()
        // `runNow` looks the folder up by id in the *stored* rule set, so it has
        // to be stored — an engine that never saved one answers nothing, and
        // that silence would read here as the queue being dead.
        engine.folders = [folder()]
        try aSweptFile("a.pdf")
        let record = try XCTUnwrap(engine.history.first)
        _ = await ask(.undo, id: record.id)

        try write("b.pdf", in: root)
        let answered = expectation(description: "run now answered")
        let box = Box()
        let transport = engine.transport
        let payload = EngineReply.encode(WatchedFolderRef(id: "f"),
                                         for: EngineCommand(name: AutopilotCommand.runNow.rawValue))
        Task {
            box.data = try? await transport.send(
                EngineCommand(name: AutopilotCommand.runNow.rawValue, payload: payload))
            answered.fulfill()
        }
        await fulfillment(of: [answered], timeout: patience)

        let data = try XCTUnwrap(box.data, """
            Run now never answered after a return had been asked for over the wire — the \
            module's queue is stopped, and the hourly sweep and the FSEvents batch are on it too
            """)
        let report = try XCTUnwrap(try? JSONDecoder().decode(SweepReport.self, from: data))
        XCTAssertEqual(report.acted, 1)
    }
}
