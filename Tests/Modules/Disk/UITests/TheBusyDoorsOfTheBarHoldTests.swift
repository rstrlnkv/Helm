import XCTest
import HelmTestSupport
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// «Scan again» and «Choose another…» while something is running.
///
/// «Scan again» was dimmed only while the volume walk ran (`live`), so pressed
/// under a folder measurement it started a second scan beside the first: the
/// measurement's `defer` then found the screen moved on and never put
/// `measuring` down, which left the spinner and the second-walk guard set for
/// good. Pressed under a removal, it threw away the tree the removal's reply
/// was about to land on. The model refuses and the page dims, both
/// (Architecture/Removal.md § One removal at a time).
@MainActor
final class TheBusyDoorsOfTheBarHoldTests: XCTestCase {

    private let sub = "/Volumes/Big/Sub"

    private func tree() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900, children: [folder(sub, bytes: 600)]),
                   freeBytes: 100, filesScanned: 10, seconds: 1)
    }

    /// A finished volume scan with the model's focus on the volume.
    private func scanned(_ work: HeldWork) async -> DiskViewModel {
        let dvm = DiskViewModel(work: work,
                                store: ScanStore(directory: scratchDirectory("disk-doors")))
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)
        work.release(0, with: tree())
        await waitUntil("the result is shown") { dvm.phase == .result }
        return dvm
    }

    /// `rescan()` where the guard holds returns at once; where it is missing it
    /// parks on a scan nobody releases. A hang is not a failure, so it runs
    /// under a deadline and a missing guard fails the assertion after it.
    private func rescanUnderDeadline(_ dvm: DiskViewModel) async {
        var returned = false
        Task { await dvm.rescan(); returned = true }
        for _ in 0..<200 where !returned { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertTrue(returned, "rescan() did not return: it started a scan under a busy model")
    }

    func testScanAgainUnderAFolderMeasurementStartsNothingAndLeavesNoStuckFlag() async {
        let work = HeldWork()
        let dvm = await scanned(work)
        dvm.drill(into: sub)
        await untilParked(work, count: 1)
        XCTAssertTrue(dvm.measuring, "precondition: the folder measurement is in flight")

        await rescanUnderDeadline(dvm)
        XCTAssertEqual(work.parkedCount, 1, "a second scan started beside the measurement")

        work.release(0, with: ScanResult(root: folder(sub, bytes: 600), freeBytes: 100,
                                         filesScanned: 1, seconds: 1))
        await waitUntil("the measurement landed") { !dvm.measuring }
        XCTAssertFalse(dvm.measuring, "the measurement flag stayed set after its answer")
    }

    func testScanAgainUnderARemovalStartsNoScanAndKeepsTheTree() async {
        let work = HeldWork()
        let dvm = await scanned(work)
        work.holdTrash()
        dvm.toggleBasket(folder(sub, bytes: 600))
        Task { await dvm.emptyBasket() }
        await untilTrashing(work)

        await rescanUnderDeadline(dvm)

        XCTAssertEqual(work.parkedCount, 0, "a scan started under a removal")
        XCTAssertEqual(dvm.phase, .result)
        work.releaseTrash()
        await waitUntil("the removal is over") { !dvm.busy }
    }

    func testChooseAnotherUnderARemovalKeepsTheTree() async {
        let work = HeldWork()
        let dvm = await scanned(work)
        work.holdTrash()
        dvm.toggleBasket(folder(sub, bytes: 600))
        Task { await dvm.emptyBasket() }
        await untilTrashing(work)

        dvm.newScan()

        XCTAssertEqual(dvm.phase, .result, "the volume picker replaced the tree under a removal")
        XCTAssertNotNil(dvm.result)
        work.releaseTrash()
        await waitUntil("the removal is over") { !dvm.busy }
    }
}
