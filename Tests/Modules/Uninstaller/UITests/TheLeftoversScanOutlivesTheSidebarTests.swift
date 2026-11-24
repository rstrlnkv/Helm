import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// The Leftovers tab's scan outlives a sidebar click.
///
/// A sidebar click unmounts `OrphansView`; the scan, the ticks and the report
/// live in `OrphansModel`, which `UninstallerViewModel` owns. Mounting the tab
/// again reads the same model (`uvm.orphans`), and only `stop()` — the module
/// switched off — clears it.
@MainActor
final class TheLeftoversScanOutlivesTheSidebarTests: XCTestCase {

    private let path = "\(NSHomeDirectory())/Library/Caches/com.gone.app"
    private func work(removal: UninstallResult = UninstallResult(trashed: [], freedBytes: 0),
                      holdScan: Bool = false) -> HeldWork {
        HeldWork(orphans: [OrphanGroup(bundleID: "com.gone.app", leftovers: [
            Leftover(path: path, kind: .caches, sizeBytes: 2_048, matchedByName: false)])],
                 removal: removal, holdScan: holdScan)
    }

    func testTheScanAndTheTicksSurviveTheViewBeingMountedAgain() async {
        let uvm = modelOver(work())
        let first = OrphansView(uvm: uvm).model
        await first.scan()
        first.toggleAll()
        // The view is gone; a new one is mounted over the same view model.
        let again = OrphansView(uvm: uvm).model
        XCTAssertTrue(again === first, "the tab built a model of its own: the scan went with the view")
        XCTAssertEqual(again.groups.map(\.bundleID), ["com.gone.app"])
        XCTAssertEqual(again.selected, [path])
        XCTAssertTrue(again.scanned)
    }

    func testSwitchingTheModuleOffClearsIt() async {
        let uvm = modelOver(work())
        let model = uvm.orphans
        await model.scan()
        model.toggleAll()
        XCTAssertFalse(model.groups.isEmpty, "precondition: there is a scan to clear")
        uvm.stop()
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertTrue(model.selected.isEmpty)
        XCTAssertFalse(model.scanned)
    }

    func testAKeptTickIsJudgedByTheEngineAtThePress() async {
        // The path vanished after the scan: the engine refuses it into the failed
        // list, and the batch holds the ticked path and nothing else.
        let refusal = TrashFailureInfo(path: path, reason: .systemRefused, message: "gone")
        let held = work(removal: UninstallResult(trashed: [], freedBytes: 0, failures: [refusal]))
        held.release()
        let uvm = modelOver(held)
        let model = uvm.orphans
        await model.scan()
        model.toggleAll()
        await model.trashSelected()
        XCTAssertEqual(held.lastBatch, [path], "the batch is the ticked paths, no more")
        XCTAssertEqual(model.failures.map(\.path), [path], "the refused path is named, not dropped")
    }

    func testAScanInFlightWhenTheModuleStopsDoesNotRefillIt() async {
        let held = work(holdScan: true)
        let uvm = modelOver(held)
        let model = uvm.orphans
        let scan = Task { await model.scan() }
        await waitUntil("the scan is running") { model.scanning }
        uvm.stop()
        held.releaseScan()
        await scan.value
        XCTAssertTrue(model.groups.isEmpty, "a scan answered after stop() and refilled the cleared list")
        XCTAssertFalse(model.scanned)
        XCTAssertFalse(model.scanning)
    }
}
