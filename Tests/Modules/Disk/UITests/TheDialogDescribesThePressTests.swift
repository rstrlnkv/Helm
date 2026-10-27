import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The sentence the person answers, against the press it starts.
///
/// The engine-side arithmetic is `TheQuestionIsAboutWhatIsSentTests`; this is the
/// other end of it — the paths the dialog names and the batch the transport is
/// actually handed in the same round.
@MainActor
final class TheDialogDescribesThePressTests: XCTestCase {
    private let caches = "/Volumes/Big/Library/Caches"
    private var children: [String] { (1...4).map { caches + "/c\($0)" } }

    private var advice: DiskAdvice {
        DiskAdvice(name: "Caches", path: caches, kind: .cache,
                   targets: children.map { DiskAdvice.Target(path: $0, bytes: 150) })
    }

    /// A scanned volume with the cache row ticked — one basket entry, four paths.
    private func scannedWithTheCacheRowTicked() async -> (DiskViewModel, AnsweringTransport) {
        let transport = AnsweringTransport(volumes: [VolumeInfo(name: "Big", path: "/Volumes/Big",
                                                                totalBytes: 1000, freeBytes: 100)])
        let tree = folder("/Volumes/Big", bytes: 600, children: [
            folder(caches, bytes: 600, children: children.map { folder($0, bytes: 150) }),
        ])
        transport.answer("/Volumes/Big",
                         with: ScanResult(root: tree, freeBytes: 100, filesScanned: 10,
                                          seconds: 1, advice: [advice]))
        transport.answerTrash(with: DiskRemoval(removed: children, refused: [], freedBytes: 600))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                store: ScanStore(directory: scratchDirectory("disk-dialog")))
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        dvm.toggleBasket(dvm.entry(for: advice))
        XCTAssertEqual(dvm.basket.count, 1, "precondition: one row, naming the folder")
        return (dvm, transport)
    }

    /// The message names the paths that go, not the folder that stays.
    func testTheMessageNamesWhatGoesAndNotWhatStays() async {
        let (dvm, _) = await scannedWithTheCacheRowTicked()

        let named = dvm.removalQuestion.named()

        XCTAssertEqual(named.split(separator: "\n").map(String.init), children)
        XCTAssertFalse(named.contains(caches + "\n"),
                       "the dialog named the folder macOS will not part with: \(named)")
    }

    /// The two halves in one round: what the sentence said, and what left. A
    /// dialog that describes a different act is only visible when both are read
    /// together.
    func testTheBatchSentIsTheBatchDescribed() async {
        let (dvm, transport) = await scannedWithTheCacheRowTicked()
        let question = dvm.removalQuestion

        await dvm.emptyBasket()

        XCTAssertEqual(transport.trashRequests, [question.paths])
        XCTAssertEqual(question.count, 4)
    }
}
