import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The removal nobody answered — the third module to carry the same fold.
///
/// `emptyBasket` folded a lost reply into zeroes: `freed` 0, no refusals, nothing
/// removed, and then «Moved to the Trash — 0 bytes» over it. Two things followed,
/// and the second is the harm. The sentence is wrong — nothing is known to have
/// moved — and it is never even drawn, because
/// `HelmRemovalOutcome.verdict(removed: 0, failed: 0)` is `.silent` and that draws
/// `EmptyView`. Meanwhile `basket = []` threw away the one piece of state in this
/// module that nothing can reconstruct: folders picked across several drills into
/// the ring, which cost a walk of the disk to find and another minute to find
/// again.
///
/// So the basket survives a lost reply, and the page says the one thing that is
/// true: Helm does not know what moved.
@MainActor
final class ALostReplyKeepsTheBasketTests: XCTestCase {

    /// Both silences the wire has. Empty `Data` is what a cached view model gets
    /// from the transport of an engine that has been switched off — the state
    /// `DiskViewModel.shared(vm:)`'s own comment describes — and a throw is what
    /// `EngineTransport.send` is declared to do; `TransportClient` folds both to
    /// the same nil.
    private static let silences: [AnsweringTransport.Answer] = [.refuse, .nothing]

    private let big = VolumeInfo(name: "Big", path: "/Volumes/Big",
                                 totalBytes: 1000, freeBytes: 100)

    override func setUp() {
        super.setUp()
        HelmLog.shared.setEnabled(true)
        HelmLog.shared.clearTail()
    }

    override func tearDown() {
        HelmLog.shared.clearTail()
        HelmLog.shared.setEnabled(false)
        super.tearDown()
    }

    private var logged: [String] {
        HelmLog.shared.recentEntries()
            .filter { $0.category == DiskEngine.moduleID }
            .map(\.message)
    }

    /// A scanned volume with one 600-byte folder ticked.
    private func scanned(_ transport: AnsweringTransport) async -> DiskViewModel {
        transport.answer("/Volumes/Big",
                         with: ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                                       children: [folder("/Volumes/Big/Sub",
                                                                         bytes: 600)]),
                                          freeBytes: 100, filesScanned: 10, seconds: 1))
        // A store of its own: the module's real one is the person's last scan,
        // and a harness must leave nothing behind.
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport),
                                store: ScanStore(directory: scratchDirectory("disk-unanswered")))
        await dvm.loadVolumes()
        await dvm.scan(path: "/Volumes/Big")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"],
                       "precondition: the folder is in the basket")
        return dvm
    }

    /// The one piece of state nothing can rebuild stays where it was.
    func testALostReplyKeepsWhatWasPicked() async {
        for silence in Self.silences {
            let transport = AnsweringTransport(volumes: [big])
            let dvm = await scanned(transport)

            transport.answers(silence)
            await dvm.emptyBasket()

            XCTAssertEqual(transport.trashRequests, [["/Volumes/Big/Sub"]],
                           "precondition: the batch really was sent (\(silence))")
            XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"], """
                a removal the engine never answered (\(silence)) emptied the basket, so the \
                folders somebody picked across several drills into the ring are gone and \
                pressing again sends nothing. Nothing is known to have moved.
                """)
        }
    }

    /// And it claims nothing about what happened — no sentence, no count, no
    /// refusal — while saying that it does not know.
    func testALostReplyClaimsNothingAndSaysSo() async {
        for silence in Self.silences {
            let transport = AnsweringTransport(volumes: [big])
            let dvm = await scanned(transport)

            transport.answers(silence)
            await dvm.emptyBasket()

            XCTAssertTrue(dvm.replyLost, """
                a removal the engine never answered (\(silence)) leaves the page with nothing to \
                say: the banner is «Moved to the Trash — 0 bytes», which the outcome row then \
                draws as `EmptyView`.
                """)
            XCTAssertNil(dvm.banner, "and it must not claim anything moved (\(silence))")
            XCTAssertEqual(dvm.removedCount, 0, "nor count anything moved (\(silence))")
            XCTAssertTrue(dvm.failures.isEmpty, "nor call anything a failure (\(silence))")
            XCTAssertTrue(dvm.showsRemovalBar,
                          "and the bar the sentence is drawn in is still there (\(silence))")
        }
    }

    /// The tree is not pruned either: nothing is known to have left it.
    func testALostReplyLeavesTheTreeAlone() async {
        let transport = AnsweringTransport(volumes: [big])
        let dvm = await scanned(transport)

        transport.answers(.nothing)
        await dvm.emptyBasket()

        XCTAssertEqual(dvm.result?.root.children.map(\.path), ["/Volumes/Big/Sub"],
                       "a folder nothing said had moved was taken off the ring")
        XCTAssertEqual(dvm.result?.root.bytes, 900)
    }

    /// And it reaches the log, under the module's own id rather than a literal —
    /// the branch a person would be attaching a log to ask about. Counts and
    /// outcomes only: nothing here names a path.
    func testALostReplySaysSoInTheLogToo() async {
        let transport = AnsweringTransport(volumes: [big])
        let dvm = await scanned(transport)

        transport.answers(.nothing)
        await dvm.emptyBasket()

        XCTAssertTrue(dvm.replyLost, "precondition: the reply really was lost")
        XCTAssertTrue(logged.contains { $0.contains("trash reply lost") }, """
            a removal whose reply never came wrote nothing to the log, so the one place a person \
            can look afterwards has no record that it happened: \(logged)
            """)
        XCTAssertFalse(logged.contains { $0.contains("Sub") },
                       "and the line must not name the folder: \(logged)")
    }

    /// An answered removal does not report a lost answer — the half that keeps the
    /// flag from being always true, which would stand a sentence nobody can act on
    /// over every successful batch.
    func testAnAnsweredRemovalDoesNotSayTheReplyWasLost() async {
        let transport = AnsweringTransport(volumes: [big])
        let dvm = await scanned(transport)
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 1, "precondition: the reply arrived and was read")
        XCTAssertFalse(dvm.replyLost, "an answered removal reports a lost answer as well")
        XCTAssertNotNil(dvm.banner, "and the sentence about what moved is drawn")
        XCTAssertTrue(dvm.basket.isEmpty, "and what moved leaves the basket")
    }

    /// A second round that *is* answered takes the sentence down, so it does not
    /// outlive the press it was about — and the basket kept above is what makes
    /// that second round possible at all.
    func testAnAnsweredRetryTakesTheLostReplyReportDown() async {
        let transport = AnsweringTransport(volumes: [big])
        let dvm = await scanned(transport)

        transport.answers(.nothing)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.replyLost, "precondition: the first round's reply was lost")

        transport.answers(.reply)
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        await dvm.emptyBasket()

        XCTAssertEqual(transport.trashRequests.count, 2,
                       "precondition: the retry sent the same batch again")
        XCTAssertFalse(dvm.replyLost,
                       "the sentence about a lost answer sits over a batch that was answered")
        XCTAssertEqual(dvm.removedCount, 1)
    }

    /// A new scan is a new screen, so the sentence about the last one goes with it.
    func testAScanTakesTheLostReplyReportDown() async {
        let transport = AnsweringTransport(volumes: [big])
        let dvm = await scanned(transport)

        transport.answers(.nothing)
        await dvm.emptyBasket()
        XCTAssertTrue(dvm.replyLost, "precondition: the reply was lost")

        transport.answers(.reply)
        await dvm.rescan()

        XCTAssertFalse(dvm.replyLost, "a fresh tree carries the last screen's silence")
        XCTAssertFalse(dvm.showsRemovalBar, "and draws a bar with nothing in it")
    }
}
