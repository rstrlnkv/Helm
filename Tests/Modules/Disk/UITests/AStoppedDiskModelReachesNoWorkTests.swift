import XCTest
import HelmContract
import HelmRuntime
import HelmTestSupport
import Module_Disk_Engine
@testable import Module_Disk_UI

/// After `stop()` a press on the page reaches no work, and before `appear()` the
/// model has read nothing.
///
/// The host calls the descriptor's `stop(_:)` before the engine's `deactivate()`:
/// on the person's switch and on quit. A page still on screen (or a task already
/// queued) may press a control after that; a scan, a removal or a volume read
/// sent to a deactivated engine is work nobody asked the module to do any more.
/// Each press below is counted at the fake, and for every press but Stop and New
/// scan the count before `stop()` is the control that proves the fake would have
/// counted it; those two are pressed only after `stop()`, and a mutant of the
/// `closed` check in `cancel()` is what shows the fake counts them.
@MainActor
final class AStoppedDiskModelReachesNoWorkTests: XCTestCase {

    private final class CountingWork: DiskWork, @unchecked Sendable {
        private let lock = NSLock()
        private var counts = (volumes: 0, scans: 0, cancels: 0, trashes: 0, background: 0)
        var volumes: Int { lock.withLock { counts.volumes } }
        var scans: Int { lock.withLock { counts.scans } }
        var cancels: Int { lock.withLock { counts.cancels } }
        var trashes: Int { lock.withLock { counts.trashes } }
        var background: Int { lock.withLock { counts.background } }

        func mountedVolumes() async -> [VolumeInfo] {
            lock.withLock { counts.volumes += 1 }
            return []
        }
        func scan(path: String, unattended: Bool,
                  updates: (@Sendable (DiskScanUpdate) -> Void)?) async -> ScanResult? {
            lock.withLock { counts.scans += 1 }
            return ScanResult(root: folder(path, bytes: 900,
                                           children: [folder(path + "/Sub", bytes: 600)]),
                              freeBytes: 100, filesScanned: 3, seconds: 1)
        }
        func cancel() { lock.withLock { counts.cancels += 1 } }
        func trash(_ paths: [String]) async -> DiskRemoval {
            lock.withLock { counts.trashes += 1 }
            return DiskRemoval(removed: [], refused: [], freedBytes: 0)
        }
        func backgroundScan() async -> ScanReport? {
            lock.withLock { counts.background += 1 }
            return nil
        }
    }

    private func model(_ work: DiskWork) -> DiskViewModel {
        DiskViewModel(work: work, store: ScanStore(directory: scratchDirectory("disk-stopped")))
    }

    func testAPressAfterStopReachesNoWork() async {
        let work = CountingWork()
        let dvm = model(work)

        // Control: the same presses reach the work while the model lives.
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        XCTAssertEqual(dvm.basket.count, 1, "precondition: the folder is in the basket")
        await dvm.emptyBasket()
        _ = await dvm.backgroundScan()
        // A folder with no children is the depth the scan stopped at: drilling
        // into it measures it, which is a second scan.
        dvm.drill(into: "/Volumes/Big/Sub")
        await settle()
        XCTAssertEqual(work.scans, 2, "control: the folder measurement reaches the work before stop()")
        XCTAssertEqual(work.volumes, 1, "control: the volume read reaches the work before stop()")
        XCTAssertEqual(work.trashes, 1, "control: the removal reaches the work before stop()")
        XCTAssertEqual(work.background, 1, "control: the background scan reaches the work before stop()")

        let (v, s, t, b) = (work.volumes, work.scans, work.trashes, work.background)
        let c = work.cancels
        dvm.stop()
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        dvm.drill(into: "/Volumes/Big/Sub/Sub")   // the measured folder's own bottom
        await settle()
        // After the scan: a scan that got as far as its own bookkeeping would
        // have emptied the basket, and the press below would have nothing to send.
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        XCTAssertEqual(dvm.basket.count, 1, "precondition: something is in the basket to send")
        await dvm.emptyBasket()
        let report = await dvm.backgroundScan()

        XCTAssertNil(report)
        XCTAssertEqual(dvm.phase, .result, "a scan after stop() left the screen mid-scan")
        XCTAssertEqual(work.volumes, v, "a volume read was sent after stop()")
        XCTAssertEqual(work.scans, s, "a scan was sent after stop()")
        XCTAssertEqual(work.trashes, t, "a removal was sent after stop()")
        XCTAssertEqual(work.background, b, "a background scan was sent after stop()")
        // Stop and New scan, pressed last: both move the screen.
        dvm.cancel()
        dvm.newScan()
        XCTAssertEqual(work.cancels, c, "a cancel was sent after stop()")
    }

    /// Dropping the module's parts drops the model: nothing the descriptor built
    /// holds it once `stop()` has run, so the tree a scan left in it is freed.
    func testAStoppedModelIsReleasedWithItsParts() async {
        weak var released: DiskViewModel?
        do {
            let dvm = model(CountingWork())
            released = dvm
            await dvm.appear()
            dvm.stop()
        }
        await settle()
        XCTAssertNil(released, "a stopped model is still held after its owner let go")
    }

    /// `makeModule` builds the model when the module starts, before anybody has
    /// opened Disk. The saved scan is an index of every file on the volume; reading it then would put that
    /// read on every launch. It is read when the page or the tile first appears.
    func testAPlantedScanIsNotReadUntilTheModelAppears() async throws {
        let directory = scratchDirectory("disk-not-appeared")
        let store = ScanStore(directory: directory)
        let root = scratchDirectory("disk-not-appeared-root")
        store.save(ScanResult(root: DiskEntry(name: root.lastPathComponent, path: root.path,
                                              bytes: 10, isDirectory: true, noAccess: false,
                                              children: []),
                              freeBytes: 0, filesScanned: 1, seconds: 1))
        let dvm = DiskViewModel(work: CountingWork(), store: store)
        await settle()
        XCTAssertEqual(dvm.phase, .start, "the model read the saved scan before it appeared")
        XCTAssertNil(dvm.result)

        await dvm.appear()
        for _ in 0..<200 where dvm.result == nil { await Task.yield() }
        XCTAssertNotNil(dvm.result, "control: the saved scan is read once the model appears")
    }
}
