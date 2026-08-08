import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
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
/// follow, and both are pinned below: the header says the walk was stopped, and
/// the tree is never written to the store, because the store is what the module
/// reopens on and labels a measurement.
///
/// `StopLeavesNothingBehindTests` is the other half — what Stop must *not* leave
/// behind on the screens that do still empty. The transport here parks every
/// scan so a walk can be caught mid-flight, which is the state that test's
/// immediate transport cannot reach.
@MainActor
final class StopKeepsWhatItMeasuredTests: XCTestCase {

    // MARK: - Fixtures

    /// A snapshot of a walk in progress: the folder is charged with what has been
    /// counted so far, which is the point — 600 of an unknown total.
    private func partOfBig(files: Int = 1_200) -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                children: [folder("/Volumes/Big/Sub", bytes: 600)]),
                   freeBytes: 100, filesScanned: files, seconds: 0)
    }

    private func model(_ transport: HeldTransport) -> (DiskViewModel, ScanStore) {
        // A store of its own: the module's real one is the person's last scan,
        // and a harness must leave nothing behind. `temporaryStoreDirectory`
        // owns the teardown, and it *drains* — a one-shot `removeItem` beside
        // it was the very race that helper exists to close.
        let store = ScanStore(directory: temporaryStoreDirectory("disk-stopkeep"))
        return (DiskViewModel(vm: ModuleViewModel(transport: transport), store: store), store)
    }

    /// A walk in flight with one snapshot drawn — the state the Stop button is
    /// visible in, and the only state this file is about.
    private func walkingWithASnapshot(
        _ transport: HeldTransport, _ dvm: DiskViewModel
    ) async {
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.emitPartial(scan: transport.scanID(0), result: partOfBig())
        await settle()
        XCTAssertEqual(dvm.phase, .result, "precondition: the ring is drawn from the snapshot")
        XCTAssertTrue(dvm.live, "precondition: the walk is still running")
    }

    // MARK: - The tree stays

    func testStopKeepsTheTreeTheWalkHadBuilt() async {
        let transport = HeldTransport()
        let (dvm, _) = model(transport)
        await walkingWithASnapshot(transport, dvm)

        dvm.cancel()                    // the Stop button

        XCTAssertEqual(dvm.phase, .result,
                       "Stop threw away the tree and showed the volume picker")
        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big")
        XCTAssertFalse(dvm.live, "the walk is over")
        XCTAssertTrue(dvm.stopped, "and the screen has to be able to say the tree is unfinished")
        XCTAssertFalse(dvm.treeIsComplete)
    }

    /// The count the header shows is the count the snapshot carried, so the line
    /// describes this walk and not a previous one.
    func testTheStoppedTreeKeepsTheCountItReached() async {
        let transport = HeldTransport()
        let (dvm, _) = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.emitPartial(scan: transport.scanID(0), result: partOfBig(files: 4_242))
        await settle()

        dvm.cancel()

        XCTAssertEqual(dvm.result?.filesScanned, 4_242)
    }

    /// Stop inside the first third of a second, before the engine has reported
    /// anything: there is no tree to keep, so this is the volume picker as it
    /// always was.
    func testStopBeforeTheFirstSnapshotShowsTheVolumePicker() async {
        let transport = HeldTransport()
        let (dvm, _) = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        XCTAssertNil(dvm.result, "precondition: nothing has been drawn yet")

        dvm.cancel()

        XCTAssertEqual(dvm.phase, .start)
        XCTAssertFalse(dvm.stopped, "there is no tree, so there is nothing to call unfinished")
    }

    /// A walk that finished is not a walk that was stopped. `cancel()` is not the
    /// Stop button — `newScan()` calls it too, and so does Stop on a screen where
    /// the walk has already ended — so the flag is driven by whether a walk was
    /// running, not by who called.
    func testAFinishedTreeIsNeverMarkedStopped() async {
        let transport = HeldTransport()
        let (dvm, _) = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: partOfBig())
        await settle()
        XCTAssertFalse(dvm.live, "precondition: the walk answered")

        dvm.cancel()

        XCTAssertFalse(dvm.stopped, "a finished measurement was labelled incomplete")
        XCTAssertTrue(dvm.treeIsComplete)
    }

    // MARK: - The basket goes with the tree it belongs to

    /// The invariant is that the basket only holds entries from the tree on
    /// screen. Stop used to satisfy it by emptying the basket, because Stop took
    /// the tree away; it satisfies it now by keeping both.
    func testStopKeepsTheBasketBecauseTheTreeIsStillOnScreen() async {
        let transport = HeldTransport()
        let (dvm, _) = model(transport)
        await walkingWithASnapshot(transport, dvm)
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
        let transport = HeldTransport()
        let (dvm, _) = model(transport)
        await walkingWithASnapshot(transport, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        dvm.cancel()
        XCTAssertFalse(dvm.basket.isEmpty, "precondition: Stop kept it")

        Task { await dvm.scan(path: "/Volumes/Small") }
        await untilParked(transport, count: 2)

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
        let transport = HeldTransport()
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = model(transport)
        await walkingWithASnapshot(transport, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))
        dvm.cancel()

        await dvm.emptyBasket()
        XCTAssertEqual(dvm.removedCount, 1, "precondition: the removal ran")
        // `saveDetached` is a detached task, so absence is only meaningful after
        // giving it room to land. The same wait sees the save in
        // `testTrashingFromAFinishedTreeDoesWriteItToTheStore` below, which is
        // what makes this assertion mean something.
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: store.fileURL.path) {
            await Task.yield()
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path),
                       "an unfinished tree was saved; the module will reopen on it "
                       + "and call it a measurement")
        XCTAssertNil(store.load())
    }

    /// The control, and the proof that the wait above is long enough to see a
    /// save: the identical sequence on a finished tree does write one.
    func testTrashingFromAFinishedTreeDoesWriteItToTheStore() async {
        let transport = HeldTransport()
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: partOfBig())
        await settle()
        XCTAssertFalse(dvm.stopped, "precondition: a finished measurement")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))

        await dvm.emptyBasket()
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: store.fileURL.path) {
            await Task.yield()
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path),
                      "a finished tree stopped being saved, so the test above proves nothing")
    }
}
