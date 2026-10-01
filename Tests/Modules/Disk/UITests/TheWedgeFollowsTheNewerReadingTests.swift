import Foundation
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The ring's free wedge draws the newer of two readings of one volume: the
/// list the tile and the volume card draw (`volumesReadAt`) and the scan's own
/// reading (`completedAt`, a restore's saved date). These walk the doors that
/// rebuild the ring without reading either again — a drill, a folder measured on
/// demand, the Trash emptied, a restore — and ask after each whether the wedge
/// still draws the newer figure, and whether one more appear brings the tile, the
/// card and the ring back to one number.
@MainActor
final class TheWedgeFollowsTheNewerReadingTests: XCTestCase {

    private let gb = 1_000_000_000
    private let root = "/Volumes/Wedge"

    private func volume(free: Int) -> VolumeInfo {
        VolumeInfo(name: "Wedge", path: root, totalBytes: 1_000 * gb, freeBytes: free)
    }

    /// A volume holding one folder with a subfolder (a drill) and one folder the
    /// walk did not open (a measurement on demand).
    private func tree(free: Int, data: Int = 900) -> ScanResult {
        ScanResult(root: folder(root, bytes: data * gb, children: [
            folder(root + "/Files", bytes: (data - 100) * gb,
                   children: [folder(root + "/Files/Sub", bytes: (data - 100) * gb)]),
            folder(root + "/Unopened", bytes: 100 * gb),
        ]), freeBytes: free, filesScanned: 10, seconds: 1)
    }

    private func wedge(_ dvm: DiskViewModel) -> Int? {
        dvm.segments.first(where: \.isFreeSpace)?.bytes
    }

    /// The figure the tile draws: the same pick `DiskWidget.main` makes.
    private func tile(_ dvm: DiskViewModel) -> Int? {
        (dvm.volumes.first { $0.path == "/" } ?? dvm.volumes.first)?.freeBytes
    }

    /// A scan of `root` answered with 100 GB free, on a list that also said 100.
    private func scanned(_ wire: AnsweringTransport) async -> DiskViewModel {
        wire.answer(root, with: tree(free: 100 * gb))
        // A folder measurement's own reading of the volume, deliberately unlike
        // either: the graft must keep the volume's figure, never this one.
        wire.answer(root + "/Unopened",
                    with: ScanResult(root: folder(root + "/Unopened", bytes: 100 * gb,
                                                  children: [folder(root + "/Unopened/In",
                                                                    bytes: 100 * gb)]),
                                     freeBytes: 777 * gb, filesScanned: 1, seconds: 1))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire),
                                store: ScanStore(directory: scratchDirectory("disk-wedge-store")))
        await dvm.loadVolumes()
        await dvm.scan(path: root)
        XCTAssertEqual(wedge(dvm), 100 * gb, "precondition: the first scan draws its free space")
        return dvm
    }

    /// Opens the unopened folder the way a click does and waits for the graft.
    private func measureTheUnopenedFolder(_ dvm: DiskViewModel) async {
        dvm.drill(into: root + "/Unopened")
        for _ in 0..<1_000 where dvm.focus?.path != root + "/Unopened" { await Task.yield() }
        await settle()
        XCTAssertEqual(dvm.focus?.path, root + "/Unopened", "precondition: the folder was measured")
    }

    // MARK: - The list read again, then a drill

    /// Appear read the list after the scan: the list is newer, so every return to
    /// the root after a drill or a measured folder draws the list.
    func testADrillAfterTheListWasReadAgainReturnsToTheList() async {
        let wire = AnsweringTransport(volumes: [volume(free: 100 * gb)])
        let dvm = await scanned(wire)
        wire.answerVolumes(with: [volume(free: 400 * gb)])
        await dvm.loadVolumes()
        XCTAssertEqual(wedge(dvm), 400 * gb, "appear: the newer list is drawn")

        dvm.drill(into: root + "/Files")
        XCTAssertNil(wedge(dvm), "a drilled ring draws a folder, never the volume's free space")
        dvm.back()
        XCTAssertEqual(wedge(dvm), 400 * gb, "drill and back: the ring left the newer list")

        await measureTheUnopenedFolder(dvm)
        XCTAssertNil(wedge(dvm))
        dvm.jump(to: 0)
        XCTAssertEqual(dvm.result?.freeBytes, 100 * gb,
                       "the graft took the folder measurement's reading as the volume's")
        XCTAssertEqual(wedge(dvm), 400 * gb, "measure and back: the ring left the newer list")
        XCTAssertEqual(wedge(dvm), tile(dvm), "the ring and the tile disagree")
    }

    // MARK: - Scan again, then a drill

    /// «Scan again» read the disk after the list: the scan is newer, and a drill
    /// or a measured folder must not hand the wedge back to the older list — nor
    /// to the folder measurement's own reading.
    func testADrillAfterScanAgainKeepsTheScansReading() async {
        let wire = AnsweringTransport(volumes: [volume(free: 100 * gb)])
        let dvm = await scanned(wire)
        wire.answerVolumes(with: [volume(free: 400 * gb)])
        wire.answer(root, with: tree(free: 400 * gb, data: 600))
        await dvm.rescan()
        XCTAssertEqual(wedge(dvm), 400 * gb, "scan again: the scan's reading is drawn")

        dvm.drill(into: root + "/Files")
        dvm.back()
        XCTAssertEqual(wedge(dvm), 400 * gb, "drill and back after scan again")

        await measureTheUnopenedFolder(dvm)
        dvm.jump(to: 0)
        XCTAssertEqual(wedge(dvm), 400 * gb, """
            measure and back after scan again drew \((wedge(dvm) ?? 0) / gb) GB: either the older \
            list (100) or the folder measurement's own reading (777)
            """)

        // The next appear brings the three surfaces to one figure.
        await dvm.loadVolumes()
        XCTAssertEqual(wedge(dvm), 400 * gb)
        XCTAssertEqual(tile(dvm), 400 * gb)
        XCTAssertEqual(dvm.volumes.first?.freeBytes, 400 * gb, "the volume card")
    }

    // MARK: - The Trash emptied

    /// Emptying the basket rebuilds the result with the old reading and the old
    /// date: whichever reading was newer before the press is newer after it.
    func testEmptyingTheTrashKeepsWhicheverReadingWasNewer() async {
        for listIsNewer in [false, true] {
            let wire = AnsweringTransport(volumes: [volume(free: 100 * gb)])
            let dvm = await scanned(wire)
            wire.answerVolumes(with: [volume(free: 400 * gb)])
            if listIsNewer {
                await dvm.loadVolumes()
            } else {
                wire.answer(root, with: tree(free: 400 * gb, data: 600))
                await dvm.rescan()
            }
            wire.answerTrash(with: DiskRemoval(removed: [root + "/Unopened"], refused: [],
                                               freedBytes: 100 * gb))
            dvm.toggleBasket(folder(root + "/Unopened", bytes: 100 * gb))
            XCTAssertFalse(dvm.basket.isEmpty, "precondition: something to empty")
            await dvm.emptyBasket()
            XCTAssertEqual(wire.trashRequests.count, 1, "precondition: the removal was sent")
            XCTAssertEqual(wedge(dvm), 400 * gb,
                           "emptied the Trash with the \(listIsNewer ? "list" : "scan") newer")
            await dvm.loadVolumes()
            XCTAssertEqual(wedge(dvm), tile(dvm), "after the next appear the ring and the tile disagree")
        }
    }

    // MARK: - Restore, then a drill

    /// A restored scan is older than the list read after it, and stays older
    /// through a drill and back.
    func testARestoredScanStaysOlderThanTheListThroughADrill() async throws {
        let mount = scratchDirectory("disk-wedge-restored").path
        let store = ScanStore(directory: scratchDirectory("disk-wedge-restored-store"))
        store.save(ScanResult(root: folder(mount, bytes: 600 * gb,
                                           children: [folder(mount + "/Files", bytes: 600 * gb,
                                                             children: [folder(mount + "/Files/In",
                                                                               bytes: 600 * gb)])]),
                              freeBytes: 39 * gb, filesScanned: 1, seconds: 1),
                   at: Date().addingTimeInterval(-60))
        let wire = AnsweringTransport(volumes: [VolumeInfo(name: "Wedge", path: mount,
                                                           totalBytes: 1_000 * gb,
                                                           freeBytes: 90 * gb)])
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire), store: store)
        for _ in 0..<1_000 where !dvm.restored || dvm.volumes.isEmpty { await Task.yield() }
        await settle()
        XCTAssertTrue(dvm.restored, "precondition: the saved ring is on screen")
        XCTAssertEqual(wedge(dvm), 90 * gb, "restore")
        dvm.drill(into: mount + "/Files")
        XCTAssertEqual(dvm.focus?.path, mount + "/Files", "precondition: drilled")
        dvm.back()
        XCTAssertEqual(wedge(dvm), 90 * gb, "restore, drill and back")
    }

    // MARK: - A saved date ahead of the clock

    /// A restore takes the file's `savedAt` as the scan's reading time, and the
    /// freshness rule compares it with the list's by the wall clock. A file saved
    /// while the clock was ahead — the clock set back afterwards, or the file
    /// brought from another Mac — carries a date later than every list this Mac
    /// will read until its clock passes that date. The restore guard
    /// (`timeIntervalSince(savedAt) <= lifetime`) admits a date in the future, and
    /// `expireIfStale` never expires one either, so what keeps the ring from
    /// drawing the saved figure beside a tile that says another is the clamp of
    /// the date in `DiskViewModel.restoreLastScan`, which this case holds.
    func testASavedDateAheadOfTheClockDoesNotOutliveTheList() async throws {
        let mount = scratchDirectory("disk-wedge-future").path
        let store = ScanStore(directory: scratchDirectory("disk-wedge-future-store"))
        // One hour ahead: a clock set back by an hour after the scan.
        store.save(ScanResult(root: folder(mount, bytes: 404 * gb,
                                           children: [folder(mount + "/Files", bytes: 404 * gb)]),
                              freeBytes: 39 * gb, filesScanned: 1, seconds: 1),
                   at: Date().addingTimeInterval(3_600))
        let wire = AnsweringTransport(volumes: [VolumeInfo(name: "Wedge", path: mount,
                                                           totalBytes: 494 * gb,
                                                           freeBytes: 90 * gb)])
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire), store: store)
        for _ in 0..<1_000 where !dvm.restored || dvm.volumes.isEmpty { await Task.yield() }
        await settle()
        XCTAssertTrue(dvm.restored, "precondition: the saved ring is on screen")
        // The page appears again, and again: each reads the list afresh.
        await dvm.loadVolumes()
        await dvm.loadVolumes()
        XCTAssertGreaterThan(wire.volumeReads, 1, "precondition: the list really was read again")
        let drawn = try XCTUnwrap(wedge(dvm), "precondition: a restored volume draws a wedge")
        XCTAssertEqual(drawn, tile(dvm), """
            a scan saved with a date an hour ahead of the clock draws \(drawn / gb) GB free on \
            the ring beside a tile that says \((tile(dvm) ?? 0) / gb) GB, after the list was \
            read again twice: the saved date is later than every list read until the clock \
            passes it.
            """)
    }
}
