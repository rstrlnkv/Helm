import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// «Run now» is live on a folder whose own switch is off, and answers with a
/// report of a sweep that did not happen.
///
/// The page draws a switch per folder and a «Run now» beside it, and the button
/// asked only whether any *rule* was enabled:
///
/// ```swift
/// .disabled(folder.rules.allSatisfy { !$0.enabled })
/// ```
///
/// **Nothing was ever at risk, and the first draft of this file said otherwise.**
/// `WatchedFolder.activeRules` is `enabled ? rules : []`, so a switched-off
/// folder runs no rules however the sweep is started — the files were safe the
/// whole time. That was found by mutation: the guard was removed and
/// `testASwitchedOffFolderIsLeftAlone` went on passing, which is the only reason
/// the claim was corrected instead of shipped.
///
/// What is real: the button looks live, and pressing it returns
/// «examined N, acted 0» — a banner reporting a sweep of a folder that is off.
/// The refusal is the engine's rather than the button's because the transport's
/// `runNow` command is a second door, and a check living in a view does not
/// stand in it.
///
/// Nothing is answered rather than an empty `SweepReport`: `FolderState` says
/// read, missing or refused, and «examined 0» is exactly the sentence that enum
/// was written to stop being three different facts. The view model already
/// reads no reply as «nothing happened».
final class ASwitchedOffFolderIsNotSweptByHandTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine(
            store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                   backing: InMemoryKeyValueStore()),
            home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
    }

    private func folder(enabled: Bool) -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: enabled,
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])],
                                   action: .move(to: root.appendingPathComponent("Sorted").path))],
                      depth: 1)
    }

    private func ask() async throws -> Data? {
        let payload = EngineReply.encode(
            WatchedFolderRef(id: "f"),
            for: EngineCommand(name: AutopilotCommand.runNow.rawValue))
        return try await engine.transport.send(
            EngineCommand(name: AutopilotCommand.runNow.rawValue, payload: payload))
    }

    /// The control: with the folder on, the same command really moves the file.
    /// Without this the refusal below could be the harness never reaching a
    /// sweep at all, and an absence would prove nothing.
    func testTheSameCommandMovesTheFileWhenTheFolderIsOn() async throws {
        engine.folders = [folder(enabled: true)]
        let file = try write("a.pdf", in: root)
        _ = try await ask()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "precondition: run now did not sweep an enabled folder")
    }

    /// The files, which were never in danger — `activeRules` already refused
    /// them. Kept because it is the claim somebody will make about this code
    /// again, and a test is a cheaper answer than re-reading three files.
    func testASwitchedOffFolderIsLeftAlone() async throws {
        engine.folders = [folder(enabled: false)]
        let file = try write("a.pdf", in: root)

        _ = try await ask()

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), """
            «Run now» moved a file out of a folder the page draws as switched off. \
            `WatchedFolder.activeRules` is the guard that holds this — `enabled ? rules \
            : []` — and it is the reason the button being live was a confusing report \
            rather than a lost file.
            """)
    }

    /// And it answers nothing, so the page shows no report of a sweep that did
    /// not happen.
    func testItAnswersNothingRatherThanAnEmptyReport() async throws {
        engine.folders = [folder(enabled: false)]
        _ = try write("a.pdf", in: root)

        let data = try await ask()

        XCTAssertEqual(data?.isEmpty ?? true, true, """
            a report came back for a sweep that was refused. «Examined 0» is what \
            `FolderState` exists to stop being three different facts, and «the folder \
            is off» is a fourth it cannot say.
            """)
    }
}
