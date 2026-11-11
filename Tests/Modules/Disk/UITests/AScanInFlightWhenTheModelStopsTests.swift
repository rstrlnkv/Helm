import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Inputs the stop tests do not feed: the answer or a snapshot arriving after
/// `stop()`, and `appear()` called after `stop()`.
@MainActor
final class AScanInFlightWhenTheModelStopsTests: XCTestCase {

    private func answer(_ path: String) -> ScanResult {
        ScanResult(root: folder(path, bytes: 900, children: [folder(path + "/Sub", bytes: 600)]),
                   freeBytes: 100, filesScanned: 3, seconds: 1)
    }

    /// The scan's answer arrives after the module was switched off: nothing of
    /// it reaches the screen and nothing is written to the saved-scan store.
    func testAnAnswerAfterStopIsNeitherShownNorSaved() async {
        let directory = scratchDirectory("disk-stop-inflight")
        let store = ScanStore(directory: directory)
        let work = HeldWork()
        let dvm = DiskViewModel(work: work, store: store)
        let walk = Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)
        XCTAssertEqual(dvm.phase, .scanning, "precondition: the walk is in flight")

        dvm.stop()
        work.emitPartial(0, result: answer("/Volumes/Big"))
        work.release(0, with: answer("/Volumes/Big"))
        await walk.value
        await settle()

        XCTAssertNil(dvm.result, "a snapshot or an answer reached a stopped model's screen")
        let saved = await store.loadDetached()
        XCTAssertNil(saved, "a stopped model wrote its late answer to the saved-scan store")
    }

    /// `appear()` arriving after `stop()` (a task queued before the switch) reads
    /// nothing back and registers no observer.
    func testAppearAfterStopReadsNoSavedScan() async {
        let directory = scratchDirectory("disk-stop-appear")
        let store = ScanStore(directory: directory)
        let root = scratchDirectory("disk-stop-appear-root")
        store.save(ScanResult(root: DiskEntry(name: root.lastPathComponent, path: root.path,
                                              bytes: 10, isDirectory: true, noAccess: false,
                                              children: []),
                              freeBytes: 0, filesScanned: 1, seconds: 1))
        let dvm = DiskViewModel(work: HeldWork(), store: store)
        dvm.stop()
        await dvm.appear()
        await settle()
        XCTAssertNil(dvm.result, "a stopped model read the saved scan back on appear()")
    }
}
