import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// What emptying the basket may claim.
///
/// `HelmTrash` moves the paths to `~/.Trash`, which is a folder on the same
/// volume: the bytes changed parent and nothing else. `emptyBasket` nevertheless
/// rebuilt the result as `freeBytes: previous.freeBytes + freed`, so the ring's
/// pale wedge and the "free" figure beside it grew by an amount no disk had
/// gained — and stayed wrong until the next real scan, because the number is
/// then saved to `ScanStore` and restored on the next launch.
///
/// The honest half is the other one: `DiskTreePrune` takes the removed subtrees
/// out of the tree, so what the volume is *using* falls by exactly what left.
///
/// This is not the same claim as `StopLeavesNothingBehindTests`, which reaches
/// `emptyBasket` across a Stop. Once Stop empties the basket that test's
/// removal is a no-op — it passes with the arithmetic never running — so the
/// arithmetic is pinned here, on the single-volume path the button actually
/// takes.
@MainActor
final class TrashIsNotFreedSpaceTests: XCTestCase {

    private final class AnsweringTransport: EngineTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var results: [String: ScanResult] = [:]
        private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
        let volumes: [VolumeInfo]
        let events: AsyncStream<EngineEvent>

        init(volumes: [VolumeInfo]) {
            self.volumes = volumes
            events = AsyncStream { _ in }
        }

        func answer(_ path: String, with result: ScanResult) {
            lock.lock(); results[path] = result; lock.unlock()
        }

        func answerTrash(with removal: DiskRemoval) {
            lock.lock(); self.removal = removal; lock.unlock()
        }

        private func result(for path: String) -> ScanResult? {
            lock.lock(); defer { lock.unlock() }; return results[path]
        }

        private var currentRemoval: DiskRemoval {
            lock.lock(); defer { lock.unlock() }; return removal
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch command.name {
            case "volumes":
                return (try? JSONEncoder().encode(volumes)) ?? Data()
            case "scan":
                let request = try? JSONDecoder().decode(ScanRequest.self, from: command.payload)
                return (try? JSONEncoder().encode(request.flatMap { result(for: $0.path) })) ?? Data()
            case "trash":
                return (try? JSONEncoder().encode(currentRemoval)) ?? Data()
            default:
                return Data()
            }
        }
    }

    // MARK: - Fixtures

    private let big = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                 totalBytes: 1000, freeBytes: 100)

    private func folder(_ path: String, bytes: Int, children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                  isDirectory: true, noAccess: false, children: children)
    }

    /// A scanned volume with one 600-byte folder ticked, and a transport that
    /// says the move succeeded.
    private func scannedWithABasketedFolder() async -> DiskViewModel {
        let transport = AnsweringTransport(volumes: [big])
        transport.answer("/Volumes/Big",
                         with: ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                                       children: [folder("/Volumes/Big/Sub",
                                                                         bytes: 600)]),
                                          freeBytes: 100, filesScanned: 10, seconds: 1))
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        // A store of its own: the module's real one is the person's last scan,
        // and a harness must leave nothing behind.
        let directory = temporaryStoreDirectory("disk-trash")
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
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

    /// The sentence under the ring. It named an outcome that had not happened:
    /// "Removed — 600 bytes freed" of files sitting in the Trash, whole.
    func testTheBannerReportsTheMoveRatherThanFreedSpace() async {
        let dvm = await scannedWithABasketedFolder()

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.banner, DkStr.movedToTrash(Bytes(600)),
                       "the banner promises space that only emptying the Trash gives back")
    }
}
