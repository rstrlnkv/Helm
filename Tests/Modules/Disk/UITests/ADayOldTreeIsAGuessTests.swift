import XCTest
import HelmTestSupport
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// «A day-old tree is a guess, not a measurement.»
///
/// `expireIfStale` is the whole of that rule and it had no test of any kind —
/// neither the boundary, nor the states it must not fire in. It is called from
/// the page's `.task`, so it runs on every appearance of the module: getting it
/// wrong in one direction shows somebody yesterday's ring as fact, and in the
/// other throws away a tree that took a minute to walk because they switched
/// tabs.
///
/// `now:` is a parameter of the method for exactly this reason — the clock is
/// not something a test may wait for — so nothing here sleeps.
@MainActor
final class ADayOldTreeIsAGuessTests: XCTestCase {

    private func result() -> ScanResult {
        ScanResult(root: folder("/Volumes/Big", bytes: 900,
                                children: [folder("/Volumes/Big/Sub", bytes: 600)]),
                   freeBytes: 100, filesScanned: 1_200, seconds: 4)
    }

    /// A model showing a finished measurement, with the store it saved it to.
    private func showingAFinishedScan() async -> (DiskViewModel, ScanStore) {
        let transport = HeldTransport()
        let store = ScanStore(directory: scratchDirectory("disk-stale"))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport), store: store)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.release(0, with: result())
        await settle()
        XCTAssertEqual(dvm.phase, .result, "precondition: a tree is on screen")
        XCTAssertNotNil(dvm.completedAt, "precondition: it is dated")
        return (dvm, store)
    }

    func testATreeOlderThanADayIsPutDownWhenThePageAppears() async throws {
        let (dvm, store) = await showingAFinishedScan()
        let measuredAt = try XCTUnwrap(dvm.completedAt)
        // Asserted before it is asked to go: «the file is not there» is green
        // over a save that never landed.
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: store.fileURL.path) {
            await Task.yield()
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path),
                      "precondition: the measurement was written down")

        dvm.expireIfStale(now: measuredAt + DiskViewModel.cacheLifetime + 1)

        XCTAssertEqual(dvm.phase, .start, "yesterday's ring was presented as a measurement")
        XCTAssertNil(dvm.result)
        // And the file goes with it: the module reopens on the store, so a tree
        // too old to draw is too old to keep.
        for _ in 0..<200 where FileManager.default.fileExists(atPath: store.fileURL.path) {
            await Task.yield()
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    /// The boundary itself. A tree exactly one lifetime old is still the
    /// measurement it was a moment before — this is `>`, not `>=`, and a test
    /// only of "much older" would pass either way.
    func testATreeExactlyOneLifetimeOldIsStillTheMeasurementItWas() async throws {
        let (dvm, _) = await showingAFinishedScan()
        let measuredAt = try XCTUnwrap(dvm.completedAt)

        dvm.expireIfStale(now: measuredAt + DiskViewModel.cacheLifetime)

        XCTAssertEqual(dvm.phase, .result, "a tree was thrown away at the moment it turned stale")
        XCTAssertNotNil(dvm.result)
    }

    /// The state that matters most: the page reappears while the walk is still
    /// running. There is no completed measurement to judge, and expiring here
    /// would empty the screen out from under a scan the person is watching.
    func testAWalkInFlightIsNeverExpired() async {
        let transport = HeldTransport()
        let store = ScanStore(directory: scratchDirectory("disk-stale-live"))
        let dvm = DiskViewModel(vm: ModuleViewModel(transport: transport), store: store)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)
        transport.emitPartial(scan: transport.scanID(0), result: result())
        await settle()
        XCTAssertTrue(dvm.live, "precondition: the walk is running and the ring is drawn")

        dvm.expireIfStale(now: Date() + 10 * DiskViewModel.cacheLifetime)

        XCTAssertEqual(dvm.phase, .result, "the walk in flight lost its screen")
        XCTAssertTrue(dvm.live, "and the walk itself was called off")
    }
}
