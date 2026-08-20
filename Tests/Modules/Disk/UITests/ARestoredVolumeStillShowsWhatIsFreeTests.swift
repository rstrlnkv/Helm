import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// Free space is drawn for a volume and not for a folder, and which of the two
/// is on screen is decided by a list that arrives later than the tree.
///
/// `recomputeSegments` asks `isVolumeScan`, which is a membership test of
/// `scannedPath` against `volumes` — a list that comes back over the transport.
/// `restoreLastScan` puts the cached tree on screen and lays it out **before**
/// that list exists, and nothing lays it out again once it does: the model's own
/// `resolveRootTitle` loads the volumes a moment later and sets only the title.
///
/// So a restored whole-volume scan settles holding both halves of the answer and
/// a ring built from neither: `volumes` says this is a volume, `segments` says
/// there is nothing free. That is not a cosmetic wedge — every arc on the ring is
/// a share of `data + free`, so leaving the free part out spreads the used bytes
/// over the whole circle and every angle on screen is wrong, on the screen that
/// exists to say where the space went. It is the same failure
/// `recomputeSegments`' own comment describes from the other side, arriving by
/// the restore door instead of the folder-scan one.
@MainActor
final class ARestoredVolumeStillShowsWhatIsFreeTests: XCTestCase {

    /// A real directory, because `restoreLastScan` refuses a tree whose root has
    /// gone — «a memory of a folder that no longer exists is not worth showing».
    /// It stands in for the mount point of a volume.
    private func volumeRoot() -> URL { scratchDirectory("disk-restored-volume") }

    private func cachedVolumeScan(at root: URL) -> ScanResult {
        ScanResult(root: folder(root.path, bytes: 600,
                                children: [folder(root.path + "/Files", bytes: 600)]),
                   freeBytes: 400, filesScanned: 12, seconds: 1)
    }

    private func transport(for root: URL) -> AnsweringTransport {
        AnsweringTransport(volumes: [VolumeInfo(name: "Scratch", path: root.path,
                                                totalBytes: 1_000, freeBytes: 400)])
    }

    /// The model with a saved scan already in its store, settled.
    private func restored(_ root: URL,
                          _ transport: AnsweringTransport) async -> DiskViewModel {
        let store = ScanStore(directory: scratchDirectory("disk-restored-store"))
        store.save(cachedVolumeScan(at: root), at: Date())
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport), store: store)
        // The restore is a detached read followed by a title lookup that loads
        // the volume list; both have to land before the question is asked.
        for _ in 0..<1_000 where !dvm.restored || dvm.volumes.isEmpty { await Task.yield() }
        await settle()
        return dvm
    }

    func testARestoredVolumeScanStillDrawsWhatIsFreeOnIt() async {
        let root = volumeRoot()
        let dvm = await restored(root, transport(for: root))

        XCTAssertTrue(dvm.restored, "precondition: the cached tree is on screen")
        XCTAssertEqual(dvm.scannedPath, root.path)
        XCTAssertTrue(dvm.volumes.contains { $0.path == dvm.scannedPath },
                      "precondition: the model knows this root is a volume")
        XCTAssertFalse(dvm.segments.isEmpty, "precondition: the ring was laid out at all")

        XCTAssertTrue(dvm.segments.contains(where: \.isFreeSpace), """
            a restored volume scan drew no free space. `restoreLastScan` lays the ring out \
            before the volume list has arrived, so `isVolumeScan` is false at that moment and \
            nothing lays it out again once the list lands — every arc is then a share of the \
            used bytes alone.
            """)
    }

    /// The control: the same tree, the same volume list, measured rather than
    /// restored. It has to draw the wedge, or the assertion above is about a
    /// fixture that could never produce one.
    func testAVolumeScanJustMeasuredDrawsIt() async {
        let root = volumeRoot()
        let wire = transport(for: root)
        wire.answer(root.path, with: cachedVolumeScan(at: root))
        let store = ScanStore(directory: scratchDirectory("disk-measured-store"))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: wire), store: store)
        await dvm.loadVolumes()

        await dvm.scan(path: root.path)

        XCTAssertFalse(dvm.segments.isEmpty, "precondition: the ring was laid out at all")
        XCTAssertTrue(dvm.segments.contains(where: \.isFreeSpace),
                      "the fixture cannot produce a free-space wedge, so the test above "
                      + "proves nothing")
    }
}
