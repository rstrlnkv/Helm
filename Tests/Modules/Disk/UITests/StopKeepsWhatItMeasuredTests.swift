import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// What Stop keeps, now that it keeps something.
///
/// A volume walk takes up to a minute and the ring is drawn from partial
/// snapshots while it runs, so the person watching has a tree in front of them
/// the whole time. Stop used to put the phase back to `.start` — the volume
/// picker — and the minute of watching was gone, even though `result` still held
/// the tree it had drawn. Nothing had to be recomputed to keep it; what was
/// missing was a way for the screen to say the tree is unfinished.
///
/// It matters that it says so. `TreeBuilder` charges a directory as its files are
/// found, so **every folder in a stopped tree shows a floor, not a total** — and
/// that is the number somebody reads when they decide to bin it. Two things
/// follow: the header says the walk was stopped (the flag it is drawn
/// from is `dvm.stopped`; no test reads the header itself), and the tree is never written to the store, which is pinned below,
/// because the store is what the module reopens on and labels a measurement.
///
/// `StopLeavesNothingBehindTests` is the other half — what Stop must *not* leave
/// behind on the screens that do still empty. The work here parks every
/// scan so a walk can be caught mid-flight, which is the state that test's
/// immediate work cannot reach.
@MainActor
final class StopKeepsWhatItMeasuredTests: XCTestCase {

    // MARK: - The basket goes with the tree it belongs to

    /// The invariant is that the basket only holds entries from the tree on
    /// screen. Stop used to satisfy it by emptying the basket, because Stop took
    /// the tree away; it satisfies it now by keeping both.
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

    /// And the door that does replace the tree empties it. This is the clearing
    /// that moved out of `cancel()`: it belongs to "a new tree is arriving", and
    /// `scan(path:)` is the only route to one — which is what stops the
    /// cross-volume arithmetic bug coming back through a different door.
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

    /// The dangerous one.
    ///
    /// `emptyBasket` applies the removal to the tree in hand rather than
    /// re-walking the disk, and then saves it — which is right for a measurement
    /// and wrong for a floor. Saved once, the module reopens on it at every
    /// launch and labels it "Measured N minutes ago": a tree the person was told
    /// was incomplete, presented to them later as fact. That is the failure
    /// "Choose another…" was added to give a way out of.
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
        // `saveDetached` is fire-and-forget, so absence is only meaningful after
        // giving it room to land. `testTrashingFromAFinishedTreeDoesWriteItToTheStore`
        // below waits for the save and asserts it, which is what makes this
        // assertion mean something.
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
