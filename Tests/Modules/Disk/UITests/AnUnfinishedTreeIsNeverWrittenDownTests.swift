import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// An unfinished tree is never written down, at the two save sites besides
/// `scan(path:)`, which saves only a walk that answered.
///
/// Every folder of an unfinished tree holds a floor, not a total, and the store
/// is what the module reopens on as «Measured N minutes ago»
/// (`StopKeepsWhatItMeasuredTests`). The two cases:
///
/// 1. A removal while the walk is still running: rows can be ticked off a
///    partial snapshot and `Move to the Trash` is dimmed only by `busy`, so
///    `emptyBasket` must not save a tree that is still being built.
/// 2. A folder measured after Stop: a stopped tree is full of folders the walk
///    never reached, which is what `drill` measures on demand, so
///    `measureAndDrill` must not save the stopped tree it grafts into.
///
/// Each case has a control proving the wait is long enough to see a save.
@MainActor
final class AnUnfinishedTreeIsNeverWrittenDownTests: XCTestCase {

    // MARK: - Fixtures

    /// What measuring `Sub` on demand comes back with.
    private func measuredSub() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big/Sub", bytes: 600,
                                children: [folder("/Volumes/Big/Sub/Inner", bytes: 600)]),
                   freeBytes: 100, filesScanned: 40, seconds: 0)
    }

    /// Room for a detached save to land. A save that is expected is waited for
    /// and asserted; one that is not gets a fixed grace, and the tests that
    /// expect it are the control that the same path still writes.
    private func waitForSave(_ store: ScanStore, lands: Bool) async {
        guard lands else { return await grace() }
        await waitUntil("a detached save landed", within: .seconds(5)) {
            FileManager.default.fileExists(atPath: store.fileURL.path)
        }
    }

    // MARK: - A removal while the walk is still running

    func testEmptyingTheBasketDuringAWalkDoesNotWriteThePartialTreeDown() async {
        let work = HeldWork()
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = heldModel(work)
        await walkingWithASnapshot(work, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 1, "precondition: the removal ran")
        XCTAssertTrue(dvm.live, "precondition: the walk is still running under it")
        await waitForSave(store, lands: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path), """
            a tree the walk had not finished was saved. `treeIsComplete` is `!stopped`, and \
            `stopped` is false while a walk is *running* — so every folder in the saved tree \
            holds a floor, and the module will reopen on it and call it a measurement.
            """)
        XCTAssertNil(store.load())
    }

    /// The control: the identical sequence on a walk that has answered writes
    /// one, so the wait above is long enough to have seen a save.
    func testEmptyingTheBasketOnAFinishedTreeStillWritesItDown() async {
        let work = HeldWork()
        work.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = heldModel(work)
        await scanned(dvm, over: work, answering: partOfBig())
        XCTAssertFalse(dvm.live, "precondition: the walk answered")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))

        await dvm.emptyBasket()

        await waitForSave(store, lands: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path),
                      "a finished tree stopped being saved, so the test above proves nothing")
    }

    // MARK: - A folder measured after Stop

    func testMeasuringAFolderOnAStoppedTreeDoesNotWriteItDown() async {
        let work = HeldWork()
        let (dvm, store) = heldModel(work)
        await walkingWithASnapshot(work, dvm)

        dvm.cancel()                                  // the Stop button
        XCTAssertTrue(dvm.stopped, "precondition: the tree on screen is a floor")

        // A folder the walk never reached, which is what a stopped tree is full
        // of: no children, so the ring cannot open it without measuring it.
        dvm.drill(into: "/Volumes/Big/Sub")
        await untilParked(work, count: 2)
        work.release(1, with: measuredSub())
        await waitUntil("the measurement is opened") { dvm.focusPath.count == 2 }

        XCTAssertEqual(dvm.focusPath.map(\.path), ["/Volumes/Big", "/Volumes/Big/Sub"],
                       "precondition: the measurement was grafted in and opened")
        await waitForSave(store, lands: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path), """
            a stopped tree was written to the store by the drill that measured one folder of \
            it. `emptyBasket` asks `treeIsComplete` before saving and `measureAndDrill` asks \
            nothing — the rest of that tree is still floors, and the module reopens on it.
            """)
        XCTAssertNil(store.load())
    }

    /// The control, and it is about the same save site: on a finished tree the
    /// drill's graft really is written down, so the absence above is the guard
    /// and not the wait.
    func testMeasuringAFolderOnAFinishedTreeWritesTheGraftDown() async {
        let work = HeldWork()
        let (dvm, store) = heldModel(work)
        await scanned(dvm, over: work, answering: partOfBig())
        XCTAssertFalse(dvm.stopped, "precondition: a finished measurement")

        // The volume walk's own request was released above and is no longer
        // parked, so the measurement is the only one waiting.
        dvm.drill(into: "/Volumes/Big/Sub")
        await untilParked(work, count: 1)
        work.release(0, with: measuredSub())
        await waitUntil("the measurement landed") { !dvm.measuring }

        // The grafted child, not merely the file: `scan(path:)` has already
        // written a tree of its own, so the file existing says nothing about
        // whether this save site fired.
        await waitUntil("the drill saved its graft, so the test above proves something",
                        within: .seconds(5)) {
            ((store.load()?.result.root).map(Self.paths(of:)) ?? []).contains("/Volumes/Big/Sub/Inner")
        }
    }

    private static func paths(of entry: DiskEntry) -> [String] {
        [entry.path] + entry.children.flatMap(paths(of:))
    }
}
