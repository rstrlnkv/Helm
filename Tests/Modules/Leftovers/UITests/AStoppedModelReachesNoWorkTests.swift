import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// After `stop()` a press on the page reaches no work.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`:
/// on the person's switch after `willDisable()` has given the switches back, and
/// on quit, where no `willDisable()` runs. A page still on screen (or a task
/// already queued) may press a control after that; a scan, a switch or a
/// removal sent to a deactivated engine is work nobody asked the module to do
/// any more. Each press below is counted at the fake, and the count before
/// `stop()` is the control that proves the fake would have counted it.
@MainActor
final class AStoppedModelReachesNoWorkTests: XCTestCase {

    private final class CountingWork: LeftoversWork, @unchecked Sendable {
        private(set) var scans = 0
        private(set) var trashes = 0
        private(set) var switches = 0
        func scan() async -> [StaleItem] {
            scans += 1
            return [StaleItem(path: "/tmp/a.plist", identifier: "com.acme.a", kind: .launchAgent,
                              sizeBytes: 4_096, status: .orphaned)]
        }
        func trash(_ paths: [String]) async -> LeftoversRemoval {
            trashes += 1
            return LeftoversRemoval(removed: [], refused: [], freedBytes: 0)
        }
        func setDisabled(_ request: LeftoversToggle) async { switches += 1 }
    }

    func testAPressAfterStopReachesNoWork() async throws {
        let work = CountingWork()
        let model = LeftoversViewModel(work: work)

        // Control: the same three presses reach the work while the model lives.
        await model.scan()
        let item = try XCTUnwrap(model.items.first, "precondition: the scan found a row")
        model.selected = [item.path]
        await model.setDisabled(true, item: item)
        await model.removeSelected()
        XCTAssertGreaterThanOrEqual(work.scans, 1)
        XCTAssertEqual(work.switches, 1, "control: the switch reaches the work before stop()")
        XCTAssertEqual(work.trashes, 1, "control: the removal reaches the work before stop()")

        let (s, w, t) = (work.scans, work.switches, work.trashes)
        model.stop()
        model.selected = [item.path]
        await model.scan()
        await model.setDisabled(false, item: item)
        await model.remove(item)
        await model.removeSelected()

        XCTAssertEqual(work.scans, s, "a scan was sent after stop()")
        XCTAssertEqual(work.switches, w, "a switch was sent after stop()")
        XCTAssertEqual(work.trashes, t, "a removal was sent after stop()")
    }
}
