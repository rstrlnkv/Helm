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
/// other end of it — the localized sentence the dialog draws, in all eight
/// languages, and the batch the transport is actually handed in the same round.
/// Measured en and ru before the repair: «Move 1 item (120 MB) to the Trash?» /
/// «Переместить 1 объект (120 МБ) в Корзину?» over four paths.
///
/// Parameterized by an explicit language, never by `AppLanguage.current`: the
/// suite runs in whatever this Mac is set to, and a count that is right in one
/// language proves nothing about the plural in the other seven.
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

    /// The title counts what will be sent, in every language — and is not the
    /// sentence the basket would have produced.
    func testTheTitleCountsThePathsAndNotTheRows() async {
        let (dvm, _) = await scannedWithTheCacheRowTicked()
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let title = DkStr.confirmTrash(dvm.removalQuestion)

            XCTAssertEqual(title,
                           HelmConfirm.trash(Plural.items(4, language: language.rawValue),
                                             Bytes(600), language: language),
                           "the question counts basket rows in \(language.rawValue)")
            XCTAssertNotEqual(title,
                              HelmConfirm.trash(Plural.items(1, language: language.rawValue),
                                                Bytes(600), language: language),
                              "still «1 item» in \(language.rawValue), for a press of four paths")
        }
    }

    /// And it names the paths that go, not the folder that stays.
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
