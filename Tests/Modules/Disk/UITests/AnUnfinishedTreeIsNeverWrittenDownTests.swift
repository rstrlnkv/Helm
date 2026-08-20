import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The two doors `treeIsComplete` does not stand in front of.
///
/// `StopKeepsWhatItMeasuredTests` pins the rule and the reason:
/// **an unfinished tree is never written down.** `TreeBuilder` charges a
/// directory as its files are found, so every folder in one reports a floor
/// rather than a total — and the store is what the module reopens on and labels
/// «Measured N minutes ago», which turns a tree the person was told is
/// incomplete into a measurement they are not.
///
/// That rule is enforced at exactly one of the three places the view model
/// saves:
///
/// * `scan(path:)` — only on a walk that answered, so nothing unfinished
///   reaches it;
/// * `emptyBasket` — asks `treeIsComplete`, which is `!stopped`;
/// * `measureAndDrill` — asks nothing at all.
///
/// Both cases below are trees the walk has not finished and `stopped` is false
/// for, which is the whole of `treeIsComplete`'s knowledge:
///
/// 1. **A removal while the walk is still running.** The bar is drawn outside
///    `switch dvm.phase`, rows can be ticked off a partial snapshot, and
///    `Move to the Trash` is dimmed only by `busy` — so this is three ordinary
///    gestures, not a corner. `stopped` is false during a live walk, so
///    `treeIsComplete` answers yes about a tree that is still being built.
/// 2. **A folder measured after Stop.** A stopped tree is exactly the tree full
///    of folders the walk never reached, and a folder with no children is what
///    `drill` measures on demand — `guard !last.children.isEmpty` — so the
///    stopped screen is the one where that path is *most* likely to be taken.
///    `measureAndDrill` grafts the answer in and saves, with no guard.
///
/// Each case is written with the control that proves the wait is long enough to
/// see a save: an absence measured with too short a wait is an absence of the
/// wait, not of the write.
@MainActor
final class AnUnfinishedTreeIsNeverWrittenDownTests: XCTestCase {

    // MARK: - Fixtures

    /// A snapshot of a walk in progress: `Sub` is charged with what has been
    /// counted so far and has no children, because the walk has not been inside
    /// it yet.
    private func partOfBig() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                children: [folder("/Volumes/Big/Sub", bytes: 600)]),
                   freeBytes: 100, filesScanned: 1_200, seconds: 0)
    }

    /// What measuring `Sub` on demand comes back with.
    private func measuredSub() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big/Sub", bytes: 600,
                                children: [folder("/Volumes/Big/Sub/Inner", bytes: 600)]),
                   freeBytes: 100, filesScanned: 40, seconds: 0)
    }

    private func model(_ transport: HeldTransport) -> (DiskViewModel, ScanStore) {
        // A store of its own: the module's real one is the person's own last
        // scan, and `scratchDirectory`'s teardown drains, which is what a save
        // arriving from the view model's own detached task needs.
        let store = ScanStore(directory: scratchDirectory("disk-unfinished"))
        return (DiskViewModel(vm: ModuleViewModel(transport: transport), store: store), store)
    }

    /// A walk in flight with one snapshot drawn — the state the ring is live in.
    private func walkingWithASnapshot(_ transport: HeldTransport,
                                      _ dvm: DiskViewModel) async {
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.emitPartial(scan: transport.scanID(0), result: partOfBig())
        await settle()
        XCTAssertEqual(dvm.phase, .result, "precondition: the ring is drawn from the snapshot")
        XCTAssertTrue(dvm.live, "precondition: the walk is still running")
    }

    /// Room for a detached save to land. The same wait sees one in the controls
    /// below, which is what makes an absence measured with it mean anything.
    private func waitForSave(_ store: ScanStore) async {
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: store.fileURL.path) {
            await Task.yield()
        }
    }

    // MARK: - A removal while the walk is still running

    func testEmptyingTheBasketDuringAWalkDoesNotWriteThePartialTreeDown() async {
        let transport = HeldTransport()
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = model(transport)
        await walkingWithASnapshot(transport, dvm)
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.removedCount, 1, "precondition: the removal ran")
        XCTAssertTrue(dvm.live, "precondition: the walk is still running under it")
        await waitForSave(store)
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
        let transport = HeldTransport()
        transport.answerTrash(with: DiskRemoval(removed: ["/Volumes/Big/Sub"],
                                                refused: [], freedBytes: 600))
        let (dvm, store) = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: partOfBig())
        await settle()
        XCTAssertFalse(dvm.live, "precondition: the walk answered")
        dvm.toggleBasket(folder("/Volumes/Big/Sub", bytes: 600))

        await dvm.emptyBasket()

        await waitForSave(store)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path),
                      "a finished tree stopped being saved, so the test above proves nothing")
    }

    // MARK: - A folder measured after Stop

    func testMeasuringAFolderOnAStoppedTreeDoesNotWriteItDown() async {
        let transport = HeldTransport()
        let (dvm, store) = model(transport)
        await walkingWithASnapshot(transport, dvm)

        dvm.cancel()                                  // the Stop button
        XCTAssertTrue(dvm.stopped, "precondition: the tree on screen is a floor")

        // A folder the walk never reached, which is what a stopped tree is full
        // of: no children, so the ring cannot open it without measuring it.
        dvm.drill(into: "/Volumes/Big/Sub")
        await untilParked(transport, count: 2)
        transport.release(1, with: measuredSub())
        await settle()

        XCTAssertEqual(dvm.focusPath.map(\.path), ["/Volumes/Big", "/Volumes/Big/Sub"],
                       "precondition: the measurement was grafted in and opened")
        await waitForSave(store)
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
        let transport = HeldTransport()
        let (dvm, store) = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: partOfBig())
        await settle()
        XCTAssertFalse(dvm.stopped, "precondition: a finished measurement")

        // The volume walk's own request was released above and is no longer
        // parked, so the measurement is the only one waiting.
        dvm.drill(into: "/Volumes/Big/Sub")
        await untilParked(transport, count: 1)
        transport.release(0, with: measuredSub())
        await settle()

        // The grafted child, not merely the file: `scan(path:)` has already
        // written a tree of its own, so the file existing says nothing about
        // whether this save site fired.
        var stored: [String] = []
        for _ in 0..<200 where !stored.contains("/Volumes/Big/Sub/Inner") {
            stored = (store.load()?.result.root).map(Self.paths(of:)) ?? []
            await Task.yield()
        }
        XCTAssertTrue(stored.contains("/Volumes/Big/Sub/Inner"),
                      "the drill stopped saving its graft, so the test above proves nothing")
    }

    private static func paths(of entry: DiskEntry) -> [String] {
        [entry.path] + entry.children.flatMap(paths(of:))
    }
}
