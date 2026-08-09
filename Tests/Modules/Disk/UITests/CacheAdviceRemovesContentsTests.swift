import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// What the + button on a Recommendations row really asks for.
///
/// From a live dev round: pressing + on `Caches — 3,84 ГБ` produced
/// `trash refused ~/Library/Caches: NSCocoaErrorDomain 513`, because macOS
/// carries `group:everyone deny delete` on that folder and on none of its
/// children. The row offered an action the app could not perform. It offers the
/// contents now — one row still, one size, one button.
@MainActor
final class CacheAdviceRemovesContentsTests: XCTestCase {
    private let caches = "/Volumes/Big/Library/Caches"
    private var firefox: String { caches + "/Firefox" }
    private var adobe: String { caches + "/Adobe" }

    private func advice() -> DiskAdvice {
        DiskAdvice(name: "Caches", path: caches, kind: .cache,
                   targets: [DiskAdvice.Target(path: firefox, bytes: 400),
                             DiskAdvice.Target(path: adobe, bytes: 200)])
    }

    /// A scanned volume whose Recommendations hold one cache row, already ticked.
    private func scannedWithTheCacheRowTicked(
        answering removal: DiskRemoval
    ) async -> (DiskViewModel, AnsweringTransport) {
        let volume = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                totalBytes: 1000, freeBytes: 100)
        let transport = AnsweringTransport(volumes: [volume])
        let tree = folder("/Volumes/Big", bytes: 600, children: [
            folder("/Volumes/Big/Library", bytes: 600, children: [
                folder(caches, bytes: 600, children: [folder(firefox, bytes: 400),
                                                      folder(adobe, bytes: 200)]),
            ]),
        ])
        transport.answer("/Volumes/Big",
                         with: ScanResult(root: tree, freeBytes: 100, filesScanned: 10,
                                          seconds: 1, advice: [advice()]))
        transport.answerTrash(with: removal)
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                store: ScanStore(directory: scratchDirectory("disk-cache-advice")))
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        dvm.toggleBasket(dvm.entry(for: advice()))
        XCTAssertEqual(dvm.basket.map(\.path), [caches],
                       "precondition: one row, naming the folder")
        return (dvm, transport)
    }

    /// The defect itself. The engine must never be handed the folder macOS
    /// protects — and the person must still have pressed one button.
    func testTheEngineIsAskedForTheContentsAndNotTheFolder() async {
        let (dvm, transport) = await scannedWithTheCacheRowTicked(
            answering: DiskRemoval(removed: [firefox, adobe], refused: [], freedBytes: 600))

        await dvm.emptyBasket()

        XCTAssertEqual(transport.trashRequests, [[firefox, adobe]])
        XCTAssertFalse(transport.trashRequests.flatMap { $0 }.contains(caches),
                       "the folder macOS refuses was handed over anyway")
    }

    /// `~/Library/Caches` has hundreds of children and some belong to running
    /// apps, so partial is the normal outcome. Every refusal reaches the screen
    /// by path and reason; none of them is summed into the count.
    func testEveryRefusalReachesTheScreenByPath() async {
        let (dvm, _) = await scannedWithTheCacheRowTicked(
            answering: DiskRemoval(removed: [firefox],
                                   refused: [HelmTrash.Refusal(path: adobe,
                                                               reason: .noPermission)],
                                   freedBytes: 400))

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.failures.map(\.path), [adobe])
        XCTAssertEqual(dvm.failures.map(\.reason), [.noPermission])
        XCTAssertEqual(dvm.removedCount, 1)
    }

    /// And the row it came from says what is left rather than what there was.
    func testThePartlyClearedRowShrinks() async {
        let (dvm, _) = await scannedWithTheCacheRowTicked(
            answering: DiskRemoval(removed: [firefox],
                                   refused: [HelmTrash.Refusal(path: adobe,
                                                               reason: .noPermission)],
                                   freedBytes: 400))

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.advice.map(\.path), [caches])
        XCTAssertEqual(dvm.result?.advice.first?.bytes, 200)
        XCTAssertEqual(dvm.result?.advice.first?.targets.map(\.path), [adobe])
    }

    /// Nothing left to offer: the row goes with its contents.
    func testAFullyClearedRowLeavesTheRecommendations() async {
        let (dvm, _) = await scannedWithTheCacheRowTicked(
            answering: DiskRemoval(removed: [firefox, adobe], refused: [], freedBytes: 600))

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.advice.count, 0)
    }
}
