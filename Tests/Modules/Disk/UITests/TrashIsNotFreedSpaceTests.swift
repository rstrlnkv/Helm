import XCTest
import HelmTestSupport
import HelmRuntime
import HelmUI
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// What emptying the basket may claim.
///
/// `HelmTrash` moves the paths to `~/.Trash`, a folder on the same volume, so
/// no space is freed and `freeBytes` stays as measured; the figure is saved to
/// `ScanStore` and would stay wrong until the next real scan. `DiskTreePrune`
/// takes the removed subtrees out of the tree, so what the volume is using
/// falls by exactly what left.
///
/// The arithmetic is pinned here, on the single-volume path the button takes;
/// `StopLeavesNothingBehindTests` reaches `emptyBasket` with an empty basket.
@MainActor
final class TrashIsNotFreedSpaceTests: XCTestCase {

    // MARK: - Fixtures

    private let big = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                 totalBytes: 1000, freeBytes: 100)

    /// A scanned volume with one 600-byte folder ticked, and a work that
    /// says the move succeeded.
    private func scannedWithABasketedFolder() async -> DiskViewModel {
        let work = AnsweringWork(volumes: [big])
        work.answer("/Volumes/Big",
                         with: ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                                       children: [folder("/Volumes/Big/Sub",
                                                                         bytes: 600)]),
                                          freeBytes: 100, filesScanned: 10, seconds: 1))
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        // A store of its own: the module's real one is the person's last scan,
        // and a harness must leave nothing behind.
        let directory = scratchDirectory("disk-trash")
        let dvm = DiskViewModel(work: work,
                                store: ScanStore(directory: directory))
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"],
                       "precondition: the folder is in the basket")
        return dvm
    }

    // MARK: -

    /// The Trash is on the volume. Nothing was freed, so the measurement stands.
    func testTrashingDoesNotAddToTheVolumesFreeSpace() async {
        let dvm = await scannedWithABasketedFolder()

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.freeBytes, 100,
                       "600 bytes that moved to ~/.Trash on this same volume were "
                       + "announced as free space the volume never gained")
    }

    /// And the half that is true: the folder leaves the tree, so the volume's
    /// used total falls by what left. Asserted as structure and as the parent's
    /// own figure — a `freeBytes` left alone would otherwise be indistinguishable
    /// from an `emptyBasket` that did nothing at all.
    func testTheRemovedFolderLeavesTheTree() async {
        let dvm = await scannedWithABasketedFolder()

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.root.children.map(\.path), [],
                       "the trashed folder is still drawn on the ring")
        XCTAssertEqual(dvm.result?.root.bytes, 300, "the volume still counts what it lost")
        XCTAssertTrue(dvm.basket.isEmpty)
    }

    /// The sentence under the ring names a move to the Trash, not freed space.
    func testTheBannerReportsTheMoveRatherThanFreedSpace() async {
        let dvm = await scannedWithABasketedFolder()

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.banner, DkStr.movedToTrash(Bytes(600)),
                       "the banner promises space that only emptying the Trash gives back")
    }
}
