import XCTest
import HelmTestSupport
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// A model nobody has opened asks the engine nothing, and after `stop()` a press
/// or an announcement reaches nothing.
///
/// The host builds the module's model once, at launch (`makeModule`), and calls the
/// descriptor's `stop(_:)` before the engine's `deactivate()`. A model that loads in
/// its init reads the rule store, and with it the keychain key, at every launch of
/// a person who never opened Autopilot; a model that still answers a press after
/// stop acts on the person's files (a sweep, a return) for a module they switched
/// off. Defect class kept: the model does work at construction, or after stop.
///
/// Every absence is paired with a control on the same fake: the fake counts the
/// same call while the model lives, so «nothing was called» cannot be a harness
/// that never reached the door.
@MainActor
final class AStoppedAutopilotModelReachesNoWorkTests: XCTestCase {

    private let home = "/Users/x"

    private func rule(_ id: String = "r") -> Rule {
        Rule(id: id, name: "sort", enabled: true, match: .all,
             conditions: [.fileExtension(["pdf"])], action: .sortIntoSubfolder(.kind))
    }

    private var folder: WatchedFolder {
        WatchedFolder(id: "f", path: home + "/Downloads", enabled: true, rules: [rule()], depth: 1)
    }

    private func record(_ id: String, run: String? = "run") -> ActionRecord {
        ActionRecord(at: Date(), rule: "sort", file: id + ".pdf", kind: .moved, detail: "",
                     path: home + "/Downloads/" + id + ".pdf",
                     destination: home + "/Downloads/PDF/" + id + ".pdf", run: run,
                     ruleID: "r", device: 1, inode: 1)
    }

    private func model(on work: FakeAutopilotWork,
                       changes: AsyncStream<Void> = AsyncStream { _ in }) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: changes,
                           presetFolders: FakePresetFolders([:]), home: home)
    }

    /// The stream the descriptor makes, one slot.
    /// The descriptor's own, so its buffering is what is under test.
    private func slot() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation) {
        AutopilotDescriptor.historyChannel()
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
        await grace()
    }

    /// Total failure of the subject prints `["readFolders", "readStatus", "readHistory"]`
    /// where `[]` is expected: the model read the engine at launch.
    func testBuildingTheModelAsksTheEngineNothing() async {
        let work = FakeAutopilotWork(folders: [folder])
        let rvm = model(on: work)
        await settle()
        XCTAssertEqual(work.calls, [],
                       "building the model reached the engine: every launch would read the rule store")
        XCTAssertTrue(rvm.folders.isEmpty, "the model held folders before any page was opened")

        // Control: the same fake is read when the page opens.
        await rvm.appear()
        XCTAssertEqual(Set(work.calls), ["readFolders", "readStatus", "readHistory"],
                       "control: appear() did not read the engine's three states")
        XCTAssertEqual(rvm.folders.map(\.id), ["f"], "control: what the engine holds did not reach the model")
    }

    func testAPressAfterStopReachesNoWork() async throws {
        let one = record("a"), two = record("b")
        let work = FakeAutopilotWork(
            folders: [folder],
            history: [one, two],
            preview: [PreviewRow(RulePlan(facts: FileFacts(name: "a.pdf", path: home + "/Downloads/a.pdf",
                                                           kind: .document, bytes: 1,
                                                           added: Date(), modified: Date()),
                                          rule: rule()))],
            report: SweepReport(folderID: "f", examined: 2, acted: 2, refused: 0, failed: 0))
        let rvm = model(on: work)
        await rvm.appear()
        let held = try XCTUnwrap(rvm.folders.first)
        let pass = try XCTUnwrap(rvm.runs.first)

        // Control: every gesture reaches the work while the model lives.
        rvm.addFolder(at: home + "/Pictures")
        await rvm.runPreview(for: held, rule: rule())
        await rvm.runNow(held)
        await rvm.undo(one)
        await rvm.undoRun(pass)
        rvm.clearHistory()
        await rvm.discardRefusedRules()
        await waitUntil("the control presses reach the work") {
            ["save", "dryRun", "sweepNow", "putBack(record:)", "putBack(run:)",
             "dropHistory", "dropRefusedRules"].allSatisfy { work.calls.contains($0) }
        }

        rvm.stop()
        await settle()
        let calls = work.calls, banner = rvm.banner, preview = rvm.preview
        rvm.addFolder(at: home + "/Music")
        rvm.remove(rule(), from: held)
        await rvm.runPreview(for: held, rule: rule())
        await rvm.runNow(held)
        await rvm.undo(one)
        await rvm.undoRun(pass)
        rvm.clearHistory()
        await rvm.discardRefusedRules()
        await rvm.loadHistory()
        await rvm.load()
        await settle()
        XCTAssertEqual(work.calls, calls, "a stopped model reached the engine: \(work.calls.dropFirst(calls.count))")
        XCTAssertEqual(rvm.banner, banner, "a stopped model drew a new banner")
        XCTAssertEqual(rvm.preview, preview, "a stopped model drew a new dry run")
    }

    func testAnAnnouncementAfterStopReadsNothing() async {
        let (changes, changed) = slot()
        let work = FakeAutopilotWork()
        let rvm = model(on: work, changes: changes)
        await rvm.appear()

        // Control: an announcement while the model lives is read.
        let before = work.count("readHistory")
        work.holdsHistory([record("a")])
        changed.yield()
        await waitUntil("a ping while the model lives is read") { work.count("readHistory") > before }

        rvm.stop()
        await settle()
        let after = work.count("readHistory")
        work.holdsHistory([record("a"), record("b")])
        changed.yield()
        await settle()
        XCTAssertEqual(work.count("readHistory"), after, "a stopped model read the history on an announcement")
        XCTAssertEqual(rvm.history.count, 1, "a stopped model drew a history it had not been told to read")
    }
}
