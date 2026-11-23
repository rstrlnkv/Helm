import HelmTestSupport
import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// A model holds a list of apps and a watch of the Applications folders only while something shows them: the page
/// and the window each watch, either may leave, and the last one to leave takes the snapshot and the watch with it.
@MainActor
final class TheWatchEndsWithTheWindowTests: XCTestCase {

    func testTheSnapshotAndTheWatchGoWithTheLastWatcherNotTheFirst() async {
        let rig = LaunchpadRig(self, label: "watch-two")
        let first = Task { await rig.model.whileShown() }
        let second = Task { await rig.model.whileShown() }
        await waitUntil("both watchers read the apps") { rig.model.snapshot != nil && rig.catalog.observers == 2 }

        first.cancel()
        await first.value
        XCTAssertNotNil(rig.model.snapshot, "one watcher left and the other lost its list")
        XCTAssertEqual(rig.catalog.observers, 1)

        second.cancel()
        await second.value
        XCTAssertNil(rig.model.snapshot, "nobody shows the apps and the model still holds them")
        XCTAssertEqual(rig.catalog.observers, 0, "the watch of the folders outlived the last watcher")
    }

    func testAReadWithNobodyWatchingHoldsNothing() async {
        let rig = LaunchpadRig(self, label: "watch-none")
        await rig.model.refresh(reason: .refresh)
        XCTAssertNil(rig.model.snapshot)
    }

    func testStopEndsEveryWatchAndTheTasksReturn() async {
        let rig = LaunchpadRig(self, label: "watch-stop")
        var returned = 0
        let tasks = (0..<2).map { _ in Task { @MainActor in await rig.model.whileShown(); returned += 1 } }
        defer { tasks.forEach { $0.cancel() } }
        await waitUntil("both watch") { rig.model.snapshot != nil && rig.catalog.observers == 2 }
        rig.model.stop()
        await waitUntil("both watchers returned after stop") { returned == 2 }
        XCTAssertNil(rig.model.snapshot)
        XCTAssertEqual(rig.catalog.observers, 0)
    }
}
