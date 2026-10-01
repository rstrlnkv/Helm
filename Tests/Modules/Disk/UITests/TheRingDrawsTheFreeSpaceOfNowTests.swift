import Foundation
import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The ring's free wedge draws the newer of two readings of the volume: the list
/// the tile and the volume card draw, and the free space the scan read at the end
/// of its walk (`DiskViewModel.recomputeSegments`). These hold the wedge to the
/// right one under every readout the port can give, and ask how old the figure
/// is when a scan has just read a newer one.
@MainActor
final class TheRingDrawsTheFreeSpaceOfNowTests: XCTestCase {

    private let gb = 1_000_000_000

    // MARK: - Scan again

    /// «Scan again» is how a person asks the ring what the disk holds now —
    /// typically after emptying the Trash the basket filled. The scan reads the
    /// volume's free space at the end of its walk and hands it over in the result,
    /// and the wedge draws it, being newer than the volume list, which was read
    /// when the page appeared and is not read again by a scan. Drawing the list
    /// would shrink the data arcs by what left while the free wedge stayed at its
    /// old size, and the whole ring would stand for a disk smaller than the one
    /// that was measured.
    func testScanAgainDrawsTheFreeSpaceTheScanRead() async throws {
        let root = scratchDirectory("disk-rescan-free").path
        let before = VolumeInfo(name: "Scratch", path: root, totalBytes: 1_000 * gb,
                                freeBytes: 100 * gb)
        let wire = AnsweringTransport(volumes: [before])
        wire.answer(root, with: ScanResult(root: folder(root, bytes: 900 * gb,
                                                        children: [folder(root + "/Files",
                                                                          bytes: 900 * gb)]),
                                           freeBytes: 100 * gb, filesScanned: 10, seconds: 1))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire),
                                store: ScanStore(directory: scratchDirectory("disk-rescan-store")))
        await dvm.loadVolumes()
        await dvm.scan(path: root)
        XCTAssertEqual(dvm.segments.first(where: \.isFreeSpace)?.bytes, 100 * gb,
                       "precondition: the first scan draws its free space")

        // The Trash emptied in Finder: 300 GB came back to the disk. The engine
        // behind this wire now answers the new figure to both questions.
        wire.answerVolumes(with: [VolumeInfo(name: "Scratch", path: root, totalBytes: 1_000 * gb,
                                             freeBytes: 400 * gb)])
        wire.answer(root, with: ScanResult(root: folder(root, bytes: 600 * gb,
                                                        children: [folder(root + "/Files",
                                                                          bytes: 600 * gb)]),
                                           freeBytes: 400 * gb, filesScanned: 10, seconds: 1))
        await dvm.rescan()

        XCTAssertEqual(dvm.result?.freeBytes, 400 * gb, "precondition: the rescan read 400 GB free")
        let wedge = try XCTUnwrap(dvm.segments.first(where: \.isFreeSpace)?.bytes)
        XCTAssertEqual(wedge, 400 * gb, """
            after «Scan again» the ring draws 600 GB of data beside a free wedge of \
            \(wedge / gb) GB, where the scan it just drew read 400 GB free: the wedge is the \
            volume list as it was when the page appeared, and a scan does not read it again.
            """)

        // The control: the same model draws the new figure once the list is read.
        await dvm.loadVolumes()
        XCTAssertEqual(dvm.segments.first(where: \.isFreeSpace)?.bytes, 400 * gb,
                       "control: the wedge cannot draw 400 GB even from a fresh list")
    }

    // MARK: - The list, the wedge and the scan agree

    /// Every readout the port has been seen to give, and the bounds beside them,
    /// through the real engine and the real transport: the volume list the tile
    /// and the volume card draw, the scan's own reading, and the ring's wedge are
    /// one figure, and used is what that figure leaves of the capacity.
    func testTheListTheScanAndTheWedgeAgreeOnEveryReadout() async throws {
        let readouts: [(String, Int?, Int?, Int?, Int)] = [
            // label, total, important, plain, the free figure Finder would show
            ("boot APFS with purgeable space", 494 * gb, 90 * gb, 39 * gb, 90 * gb),
            ("exFAT, important answers 0", 64 * gb, 0, 60 * gb, 60 * gb),
            ("full HFS+, both 0", 64 * gb, 0, 0, 0),
            ("full APFS, the reserve on both", 64 * gb, 1_814_528, 1_814_528, 1_814_528),
            ("important unreadable", 64 * gb, nil, 60 * gb, 60 * gb),
            ("important a few KB under plain", 64 * gb, 66_240_512, 66_252_800, 66_240_512),
            ("important past the capacity", 64 * gb, 70 * gb, 60 * gb, 64 * gb),
        ]
        for (label, total, important, plain, expected) in readouts {
            let root = scratchDirectory("disk-agree").path
            try Data(count: 4096).write(to: URL(fileURLWithPath: root + "/a.bin"))
            let capacity = OneVolume(VolumeReadout(name: "V", path: root, isBrowsable: true,
                                                   total: total, importantFree: important,
                                                   plainFree: plain))
            let transport = LocalTransport()
            let engine = DiskEngine(transport: transport, capacity: capacity)
            let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                    store: ScanStore(directory: scratchDirectory("disk-agree-store")))
            await dvm.loadVolumes()
            await dvm.scan(path: root)
            withExtendedLifetime(engine) {}

            let listed = try XCTUnwrap(dvm.volumes.first, "\(label): not listed")
            XCTAssertEqual(listed.freeBytes, expected, "\(label): the tile's figure")
            XCTAssertEqual(listed.usedBytes, listed.totalBytes - listed.freeBytes, label)
            XCTAssertEqual(dvm.result?.freeBytes, expected, "\(label): the scan's own reading")
            let wedge = dvm.segments.first(where: \.isFreeSpace)?.bytes ?? 0
            XCTAssertEqual(wedge, expected, "\(label): the ring's wedge")
        }
    }

    // MARK: - A volume as large as an integer

    /// Once a finding that trapped the process (the sum overflowed). The
    /// engine bounds free space to the capacity and `VolumeInfo` bounds both at
    /// zero from below, so the list can carry a free figure of `Int.max`; the
    /// wedge now reads that figure, and `RingLayout.layout` adds it to the
    /// scanned bytes. One byte of data is an overflow.
    func testAVolumeWithTheLargestFigureDoesNotTrapTheRing() async throws {
        let root = scratchDirectory("disk-largest").path
        try Data(count: 4096).write(to: URL(fileURLWithPath: root + "/a.bin"))
        let capacity = OneVolume(VolumeReadout(name: "V", path: root, isBrowsable: true,
                                               total: Int.max, importantFree: Int.max,
                                               plainFree: Int.max))
        let transport = LocalTransport()
        let engine = DiskEngine(transport: transport, capacity: capacity)
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                store: ScanStore(directory: scratchDirectory("disk-largest-store")))
        await dvm.loadVolumes()
        XCTAssertEqual(dvm.volumes.first?.freeBytes, Int.max, "precondition: the list carries Int.max")
        await dvm.scan(path: root)
        withExtendedLifetime(engine) {}
        XCTAssertFalse(dvm.segments.isEmpty, "the ring of a volume this large drew nothing")
    }
}

/// One volume, answering for any path at or under its mount point.
private struct OneVolume: VolumeCapacityPort {
    let volume: VolumeReadout
    init(_ volume: VolumeReadout) { self.volume = volume }
    func mounted() -> [VolumeReadout] { [volume] }
    func readout(at path: String) -> VolumeReadout? {
        path.hasPrefix(volume.path) ? volume : nil
    }
}
