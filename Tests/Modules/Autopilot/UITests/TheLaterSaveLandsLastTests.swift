import HelmRuntime
import XCTest
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// **Past defect: the older list could be the one stored.** Each gesture sent its
/// list in a Task of its own, `offTheCooperativePool` runs those on the global
/// concurrent queue, and so two quick edits raced for the engine's lock: the
/// earlier full-list snapshot could land last and the later edit reverted after a
/// reload. Saves now form one chain, each waiting for the one before.
///
/// The old format is untouched, only the order of writes; its guard is
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
        while work.count("save") < 1 { try? await Task.sleep(nanoseconds: 1_000_000) }
        rvm.addFolder(at: NSHomeDirectory() + "/Documents")
        // Where the saves are not chained the second one arrives now; chained, it
        // cannot, so a bounded wait stands for "had its chance".
        for _ in 0..<50 where work.count("save") < 2 { try? await Task.sleep(nanoseconds: 2_000_000) }
        work.releaseTheFirstSave()
        while work.count("save") < 2 { try? await Task.sleep(nanoseconds: 1_000_000) }
        // The page re-reads after the last write; the reload is what ends the chain.
        while work.count("readFolders") < 3 { try? await Task.sleep(nanoseconds: 1_000_000) }

        XCTAssertEqual(work.saved.map(\.count), [1, 2], "the premise: both saves reached the engine, in order")
        let stored = await work.readFolders()
        XCTAssertEqual(stored.count, 2, "the later edit is the list that stayed")
    }
}
