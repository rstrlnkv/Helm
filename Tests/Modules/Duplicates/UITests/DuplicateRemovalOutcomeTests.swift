import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// How a refusal reaches the screen.
///
/// This module hand-composed a sentence — a count, a semicolon, another count,
/// then one reason chosen for the whole batch — and the page drew it as a bare
/// `.callout`. Disk, Leftovers and the orphans tab publish the numbers and the
/// failures instead and hand them to `HelmRemovalOutcome`, whose `Verdict` logic
/// exists because "Removed — 0 bytes freed, 1 could not be moved" shipped.
///
/// A pre-baked string cannot be asked whether it is true, and it cannot name
/// the file that stayed. Asserted here on the published values, not on prose.
@MainActor
final class DuplicateRemovalOutcomeTests: XCTestCase {

    private final class RemovingTransport: EngineTransport, @unchecked Sendable {
        private let groups: [DuplicateGroup]
        private let removal: DuplicateRemoval
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

        init(groups: [DuplicateGroup], removal: DuplicateRemoval) {
            self.groups = groups
            self.removal = removal
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch command.name {
            case "find": return searchReply(groups)
            case "trash": return (try? JSONEncoder().encode(removal)) ?? Data()
            default: return Data()
            }
        }
    }

    private var first: String { "\(home)/Downloads/first.bin" }
    private var second: String { "\(home)/Downloads/second.bin" }
    private var third: String { "\(home)/Downloads/third.bin" }

    private func model(removal: DuplicateRemoval) async -> DuplicatesViewModel {
        let groups = [DuplicateGroup(copies: [.init(path: first, bytes: 1_000_000),
                                              .init(path: second, bytes: 1_000_000),
                                              .init(path: third, bytes: 1_000_000)])]
        // The key is the suite's, not the person's: `init` reads the keep policy
        // through this guard, and the default reaches `com.helm.app /
        // settings-seal` in the login keychain — creating it where it is absent.
        let dvm = DuplicatesViewModel(
            vm: ModuleViewModel(transport: RemovingTransport(groups: groups, removal: removal)),
            store: duplicatesStore(folder: "\(home)/Downloads"),
            settings: SettingGuard(keys: PlantedSealKey()))
        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        return dvm
    }

    /// One moved, one refused: both numbers are published, and the refusal
    /// carries the path and its own reason rather than one chosen for the batch.
    func testARefusalIsPublishedAsAFailureRatherThanASentence() async {
        let refusal = HelmTrash.Refusal(path: third, reason: .noPermission)
        let dvm = await model(removal: DuplicateRemoval(removed: [second],
                                                        refused: [refusal],
                                                        freedBytes: 1_000_000))
        dvm.toggleBasket(second)
        dvm.toggleBasket(third)

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 1, "the count the outcome asks for is not published")
        XCTAssertEqual(dvm.failures.map(\.path), [third],
                       "the refused path is not named anywhere the page can reach")
        XCTAssertEqual(dvm.failures.map(\.reason), [TrashFailure.Reason.noPermission])
        // What refused stays in the basket on purpose, so that the person can
        // fix the permission and press the button again. The bar therefore has
        // a basket *and* an outcome to draw at the same moment — drawing the
        // outcome only for an empty basket makes the failure list unreachable
        // in exactly the case it exists for.
        XCTAssertEqual(dvm.basket, [third], "precondition: the refusal is still ticked")
    }

    /// Nothing moved and something was refused: the success sentence must not be
    /// the thing on screen. `HelmRemovalOutcome` decides that from the numbers,
    /// so what this owes it is a `removedCount` of zero — not a banner that
    /// already claims otherwise.
    func testNothingMovedIsNotAnnouncedAsRemoval() async {
        let refusal = HelmTrash.Refusal(path: second, reason: .noPermission)
        let dvm = await model(removal: DuplicateRemoval(removed: [], refused: [refusal],
                                                        freedBytes: 0))
        dvm.toggleBasket(second)

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 0)
        XCTAssertEqual(dvm.failures.count, 1)
        XCTAssertNil(dvm.banner,
                     "a success sentence was composed for a removal that removed nothing")
    }

    /// What the dialog says before any of this happens. A count and a size name
    /// nothing, and this module deletes a person's own photos and videos — so
    /// the question names the files, the way Disk's does.
    func testTheConfirmationNamesTheFilesRatherThanCountingThem() {
        let home = NSHomeDirectory()
        let message = DuplicatesSettingsPage.confirmationMessage(
            ["\(home)/Downloads/IMG_4231.HEIC", "/Volumes/Big/clip.mov"])

        XCTAssertEqual(message, "~/Downloads/IMG_4231.HEIC\n/Volumes/Big/clip.mov",
                       "the home folder is abbreviated the way Finder abbreviates it, "
                       + "and a path outside it is left alone")
    }

    /// Five paths, four named and an ellipsis: a dialog is not a list view.
    func testALongBasketIsTruncatedWithAnEllipsis() {
        let paths = (1...5).map { "/Volumes/Big/clip-\($0).mov" }

        let lines = DuplicatesSettingsPage.confirmationMessage(paths)
            .components(separatedBy: "\n")

        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines.last, "…")
        XCTAssertEqual(Array(lines.dropLast()), Array(paths.prefix(4)))
    }

    /// A clean removal still says so, and says it once.
    func testACleanRemovalPublishesNoFailures() async {
        let dvm = await model(removal: DuplicateRemoval(removed: [second], refused: [],
                                                        freedBytes: 1_000_000))
        dvm.toggleBasket(second)

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 1)
        XCTAssertTrue(dvm.failures.isEmpty)
        // Says where the copies went, not that space came back — they are in
        // the Trash, on the same volume, and the other three modules that trash
        // things now say this in the same words.
        XCTAssertEqual(dvm.banner, DupStr.movedToTrash(Bytes(1_000_000)))
    }
}
