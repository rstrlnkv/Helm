import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// What a tick does while a removal is still in flight.
///
/// `emptyBasket` sends the paths, waits, and then writes `basket = []`, so a
/// row ticked in between would be dropped without being sent, refused or
/// mentioned. `toggleBasket` therefore refuses while `busy` is set, and the page
/// dims (Architecture/Removal.md § One removal at a time).
///
/// Every case needs a removal that is running; `HeldWork.holdTrash()` holds one.
@MainActor
final class TheBasketHoldsStillUnderARemovalTests: XCTestCase {

    private let sub = "/Volumes/Big/Sub"
    private let other = "/Volumes/Big/Other"

    private func tree() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                children: [folder(sub, bytes: 600),
                                           folder(other, bytes: 200)]),
                   freeBytes: 100, filesScanned: 10, seconds: 1)
    }

    /// A scanned volume with one folder ticked and a removal parked mid-flight.
    private func removing(_ work: HeldWork) async -> DiskViewModel {
        work.holdTrash()
        work.answerTrash(with: DiskRemoval(removed: [sub], refused: [], freedBytes: 600))
        let dvm = DiskViewModel(work: work,
                                store: ScanStore(directory: scratchDirectory("disk-busy")))
        await scanned(dvm, over: work, answering: tree())
        dvm.toggleBasket(folder(sub, bytes: 600))
        XCTAssertEqual(dvm.basket.map(\.path), [sub], "precondition: one folder is ticked")

        Task { await dvm.emptyBasket() }
        await untilTrashing(work)
        XCTAssertTrue(dvm.busy, "precondition: the removal is in flight")
        return dvm
    }

    // MARK: - The model refuses

    /// A row ticked mid-removal is refused, not taken in and then emptied away.
    func testARowTickedWhileARemovalRunsIsNotTakenAndThrownAway() async {
        let work = HeldWork()
        let dvm = await removing(work)

        dvm.toggleBasket(folder(other, bytes: 200))

        XCTAssertEqual(dvm.basket.map(\.path), [sub], """
            the basket took a row that the reply about to land is not about: \
            \(dvm.basket.map(\.path)). It is cleared wholesale when the answer comes back, \
            so this folder is dropped without being sent and without being mentioned.
            """)
        work.releaseTrash()
        await waitUntil("the removal is over") { !dvm.busy }
    }

    /// The same guard from the other side: the bar's menu unticks through the
    /// same method, and a row taken out mid-flight would be reported removed.
    func testARowUntickedWhileARemovalRunsStaysInTheBatchItWasSentIn() async {
        let work = HeldWork()
        let dvm = await removing(work)

        dvm.toggleBasket(folder(sub, bytes: 600))

        XCTAssertEqual(dvm.basket.map(\.path), [sub],
                       "the basket lost the row the removal in flight is about")
        work.releaseTrash()
        await waitUntil("the removal is over") { !dvm.busy }
    }

    /// The control: once the answer is in, the basket takes ticks again, so a
    /// guard of «never» would fail here.
    func testTheBasketTakesRowsAgainOnceTheReplyLands() async {
        let work = HeldWork()
        let dvm = await removing(work)
        work.releaseTrash()
        await waitUntil("the removal is over") { !dvm.busy }
        XCTAssertFalse(dvm.busy, "precondition: the removal is over")

        dvm.toggleBasket(folder(other, bytes: 200))

        XCTAssertEqual(dvm.basket.map(\.path), [other],
                       "the guard outlived the removal it belongs to")
    }

    /// The press itself, twice: the second «Remove» while the first is held sends
    /// nothing to the engine.
    func testASecondRemovePressWhileOneRunsSendsNothing() async {
        let work = HeldWork()
        let dvm = await removing(work)

        // Started, not awaited: with no guard the second press parks on the held
        // fake too, and awaiting it would hang instead of failing.
        let second = Task { await dvm.emptyBasket() }
        await grace()

        XCTAssertEqual(work.trashRequests, [[sub]], "a second removal reached the engine")
        work.releaseTrash()
        await second.value
        await waitUntil("the removal is over") { !dvm.busy }
    }

    /// The batch is the one that was sent: nothing added in the meantime got in,
    /// nothing removed got out. Read off `HeldWork.trashRequests`, what the engine acts on.
    func testTheEngineIsHandedExactlyWhatWasTickedWhenThePressHappened() async {
        let work = HeldWork()
        let dvm = await removing(work)
        dvm.toggleBasket(folder(other, bytes: 200))
        work.releaseTrash()
        await waitUntil("the removal is over") { !dvm.busy }

        XCTAssertEqual(work.trashRequests, [[sub]],
                       "the engine was handed a different batch from the one consented to")
    }
}
