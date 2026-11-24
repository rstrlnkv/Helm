import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Disk_Engine
@testable import Module_Disk_UI

/// «A day-old tree is a guess, not a measurement.»
///
/// `expireIfStale` is the whole of that rule, and the page's `.task` calls it
/// on every appearance: wrong one way it shows yesterday's ring as fact, wrong
/// the other it throws away a tree that took a minute to walk.
///
/// `now:` is a parameter so nothing here waits for the clock.
@MainActor
final class ADayOldTreeIsAGuessTests: XCTestCase {

    private func result() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                children: [folder("/Volumes/Big/Sub", bytes: 600)]),
                   freeBytes: 100, filesScanned: 1_200, seconds: 4)
    }

    /// A model showing a finished measurement, with the store it saved it to.
    private func showingAFinishedScan() async -> (DiskViewModel, ScanStore) {
        let work = HeldWork()
        let store = ScanStore(directory: scratchDirectory("disk-stale"))
        let dvm = DiskViewModel(work: work, store: store)
        await scanned(dvm, over: work, answering: result())
        XCTAssertEqual(dvm.phase, .result, "precondition: a tree is on screen")
        XCTAssertNotNil(dvm.completedAt, "precondition: it is dated")
        return (dvm, store)
    }

    func testATreeOlderThanADayIsPutDownWhenThePageAppears() async throws {
        let (dvm, store) = await showingAFinishedScan()
        let measuredAt = try XCTUnwrap(dvm.completedAt)
        // Asserted before it is asked to go: «the file is not there» is green
        // over a save that never landed.
        await waitUntil("precondition: the measurement was written down", within: .seconds(5)) {
            FileManager.default.fileExists(atPath: store.fileURL.path)
        }

        dvm.expireIfStale(now: measuredAt + DiskViewModel.cacheLifetime + 1)

        XCTAssertEqual(dvm.phase, .start, "yesterday's ring was presented as a measurement")
        XCTAssertNil(dvm.result)
        // And the file goes with it: the module reopens on the store, so a tree
        // too old to draw is too old to keep.
        await waitUntil("the file went with the tree", within: .seconds(5)) {
            !FileManager.default.fileExists(atPath: store.fileURL.path)
        }
    }

    /// The boundary: a tree exactly one lifetime old is still a measurement
    /// (`>`, not `>=`).
    func testATreeExactlyOneLifetimeOldIsStillTheMeasurementItWas() async throws {
        let (dvm, _) = await showingAFinishedScan()
        let measuredAt = try XCTUnwrap(dvm.completedAt)

        dvm.expireIfStale(now: measuredAt + DiskViewModel.cacheLifetime)

        XCTAssertEqual(dvm.phase, .result, "a tree was thrown away at the moment it turned stale")
        XCTAssertNotNil(dvm.result)
    }

    /// The page reappears while the walk is still running: there is no finished
    /// measurement to judge, and expiring would empty the screen under the scan.
    func testAWalkInFlightIsNeverExpired() async {
        let work = HeldWork()
        let store = ScanStore(directory: scratchDirectory("disk-stale-live"))
        let dvm = DiskViewModel(work: work, store: store)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)
        work.emitPartial(0, result: result())
        await waitUntil("the snapshot is drawn") { dvm.phase == .result }
        XCTAssertTrue(dvm.live, "precondition: the walk is running and the ring is drawn")

        dvm.expireIfStale(now: Date() + 10 * DiskViewModel.cacheLifetime)

        XCTAssertEqual(dvm.phase, .result, "the walk in flight lost its screen")
        XCTAssertTrue(dvm.live, "and the walk itself was called off")
    }
}
