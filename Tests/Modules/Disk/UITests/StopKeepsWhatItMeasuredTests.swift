import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// What a Stop mid-walk keeps: the tree drawn from the last snapshot, marked
/// `dvm.stopped`.
///
/// `TreeBuilder` charges a directory as its files are found, so every folder in
/// a stopped tree shows a floor, not a total. The header says the walk was
/// stopped (drawn from `dvm.stopped`; no test reads the header), and the tree is
/// never written to the store, which the module reopens on as a measurement.
///
/// `StopLeavesNothingBehindTests` holds the Stop that lands on the volume
/// picker. The work here parks every scan so a walk can be caught mid-flight.
@MainActor
final class StopKeepsWhatItMeasuredTests: XCTestCase {

    // MARK: - The basket goes with the tree it belongs to

    /// The basket holds only entries from the tree on screen; a Stop mid-walk
    /// keeps the tree, so it keeps the basket.
    func testStopKeepsTheBasketBecauseTheTreeIsStillOnScreen() async {
        let work = HeldWork()
        let (dvm, _) = heldModel(work)
        await walkingWithASnapshot(work, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"], "precondition")

        dvm.cancel()

        XCTAssertEqual(dvm.basket.map(\.path), ["/Volumes/Big/Sub"],
                       "the bar is over the tree these folders are part of")
    }

    /// The basket is emptied when a new tree arrives, and `scan(path:)` is the
    /// only route to one, so freed bytes are never credited across volumes.
    func testMeasuringSomewhereElseEmptiesTheBasketAStopLeftBehind() async {
        let work = HeldWork()
        let (dvm, _) = heldModel(work)
        await walkingWithASnapshot(work, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        dvm.cancel()
        XCTAssertFalse(dvm.basket.isEmpty, "precondition: Stop kept it")

        Task { await dvm.scan(path: "/Volumes/Small") }
        await untilParked(work, count: 2)

        XCTAssertTrue(dvm.basket.isEmpty,
                      "\(dvm.basket.map(\.path)) belong to a volume that is no longer on screen")
        XCTAssertFalse(dvm.stopped, "and the new walk is not the stopped one")
    }

    // MARK: - An unfinished tree is never written down

    /// `emptyBasket` applies the removal to the tree in hand and saves it, which
    /// is right for a measurement and wrong for a floor: saved, a stopped tree
    /// would reopen at every launch as "Measured N minutes ago".
    func testTrashingFromAStoppedTreeDoesNotWriteItToTheStore() async {
        let work = HeldWork()
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = heldModel(work)
        await walkingWithASnapshot(work, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        dvm.cancel()

        await dvm.emptyBasket()
        XCTAssertEqual(dvm.removedCount, 1, "precondition: the removal ran")
        // `saveDetached` is fire-and-forget, so absence means something only
        // after room to land; the control below proves the wait is long enough.
        await grace()

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path),
                       "an unfinished tree was saved; the module will reopen on it "
                       + "and call it a measurement")
        XCTAssertNil(store.load())
    }

    /// The control, and the proof that the wait above is long enough to see a
    /// save: the identical sequence on a finished tree does write one.
    func testTrashingFromAFinishedTreeDoesWriteItToTheStore() async {
        let work = HeldWork()
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = heldModel(work)
        await scanned(dvm, over: work, answering: partOfBig())
        XCTAssertFalse(dvm.stopped, "precondition: a finished measurement")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))

        await dvm.emptyBasket()
        await waitUntil("control: a finished tree is saved", within: .seconds(5)) {
            FileManager.default.fileExists(atPath: store.fileURL.path)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path),
                      "a finished tree stopped being saved, so the test above proves nothing")
    }
}
