import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Autopilot_Engine

/// «Run now» is live on a folder whose own switch is off, and answers with a
/// report of a sweep that did not happen.
///
/// The page draws a switch per folder and a «Run now» beside it. No file is at
/// risk: `WatchedFolder.activeRules` is `enabled ? rules : []`, so a
/// switched-off folder runs no rules however the sweep is started. What is
/// guarded is a live-looking press returning «examined N, acted 0», a banner
/// reporting a sweep of a folder that is off.
///
/// The refusal is the engine's rather than the button's because the model's
/// door, `sweepNow(folderID:)`, is a second door, and a check living in a view
/// does not stand in it.
final class ASwitchedOffFolderIsNotSweptByHandTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine.scratch(home: home.path)
    }

    private func folder(enabled: Bool) -> WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: enabled,
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])],
                                   action: .move(to: root.appendingPathComponent("Sorted").path))],
                      depth: 1)
    }

    private func ask() async -> SweepReport? {
        await engine.sweepNow(folderID: "f")
    }

    /// The control: with the folder on, the same command really moves the file.
    /// Without this the refusal below could be the harness never reaching a
    /// sweep at all, and an absence would prove nothing.
    func testTheSameCommandMovesTheFileWhenTheFolderIsOn() async throws {
        engine.folders = [folder(enabled: true)]
        let file = try write("a.pdf", in: root)
        let report = await ask()
        XCTAssertNotNil(report, "precondition: run now did not answer for an enabled folder")
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path),
                       "precondition: run now did not sweep an enabled folder")
    }

    /// The files are never in danger: `activeRules` refuses them. Kept because
    /// somebody will claim otherwise, and a test is a cheaper answer than
    /// re-reading three files.
    func testASwitchedOffFolderIsLeftAlone() async throws {
        engine.folders = [folder(enabled: false)]
        let file = try write("a.pdf", in: root)

        let report = await ask()

        XCTAssertNil(report, """
            «Run now» answered a report for a folder that is switched off — the banner \
            «examined N, acted 0» over a sweep that did not happen
            """)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), """
            «Run now» moved a file out of a folder the page draws as switched off. \
            `WatchedFolder.activeRules` is the guard that holds this — `enabled ? rules \
            : []` — and it is the reason the button being live was a confusing report \
            rather than a lost file.
            """)
    }
}
