import HelmTestSupport
import HelmRuntime
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **The later of two quick edits is the list stored**: saves form one chain,
/// each waiting for the one before (Architecture/Autopilot.md § How Autopilot's model reaches its engine).
///
/// The stored format is untouched, only the order of writes; its guard is
/// `RuleOverwriteTests`.
@MainActor
final class TheLaterSaveLandsLastTests: XCTestCase {

    func testTheSecondEditIsTheListThatIsStoredLast() async {
        let work = FakeAutopilotWork()
        let rvm = AutopilotViewModel(work: work, historyChanges: AsyncStream { _ in },
                                     presetFolders: FakePresetFolders([:]),
                                     home: NSHomeDirectory())
        await rvm.appear()
        work.holdsTheFirstSave()

        rvm.addFolder(at: NSHomeDirectory() + "/Downloads")
        // The first save has reached the engine and is held there.
        await waitUntil("the first save reached the engine") { work.count("save") >= 1 }
        rvm.addFolder(at: NSHomeDirectory() + "/Documents")
        // Where the saves are not chained the second one arrives now; chained, it
        // cannot, so a grace stands for "had its chance"; the control is the second save below.
        await grace(0.1)
        work.releaseTheFirstSave()
        await waitUntil("the second save reached the engine") { work.count("save") >= 2 }
        // The page re-reads after the last write; the reload is what ends the chain.
        await waitUntil("the page re-read after the last write") { work.count("readFolders") >= 3 }

        XCTAssertEqual(work.saved.map(\.count), [1, 2], "the premise: both saves reached the engine, in order")
        let stored = await work.readFolders()
        XCTAssertEqual(stored.count, 2, "the later edit is the list that stayed")
    }
}
