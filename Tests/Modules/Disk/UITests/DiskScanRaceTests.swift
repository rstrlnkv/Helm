import XCTest
import HelmTestSupport
import HelmContract
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The two orders of events the ring never survived: a snapshot from a scan the
/// screen is not showing, and an answer to a scan the user has already
/// withdrawn.
///
/// Both are reachable through one gesture. Drilling into a folder the walk has
/// not reached yet issues a *second* scan while the first is still walking, and
/// drilling is not gated on `live` — so from the moment the first partial draws
/// the ring, a click on its rim starts a scan beside the volume's. The
/// volume's walk has a sink of its own for what it says, and a folder
/// measurement asks for none; the model drops what a scan says once the screen
/// no longer belongs to it.
///
/// The work is hand-cranked: every scan parks until the test releases it, and
/// updates are pushed by hand through the sink that scan was given, so the
/// interleaving is chosen rather than raced.
@MainActor
final class DiskScanRaceTests: XCTestCase {

    // MARK: - Fixtures

    private func result(_ root: DiskEntry, freeBytes: Int = 500) -> ScanResult {
        ScanResult(root: root, freeBytes: freeBytes, filesScanned: 10, seconds: 1)
    }

    private func model(_ work: HeldWork) -> DiskViewModel {
        // A store of its own: the module's real one is the user's last scan.
        let directory = scratchDirectory("disk-race")
        return DiskViewModel(work: work,
                             store: ScanStore(directory: directory))
    }

    // MARK: - A snapshot belongs to one scan

    /// The screen has moved on to a second scan; the first one, withdrawn, is
    /// still walking and still says what it found. It must not repaint the ring.
    func testAPartialFromAWithdrawnScanDoesNotRepaintTheRing() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Old") }
        await untilParked(work, count: 1)
        dvm.cancel()
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 2)

        work.emitPartial(1, result: result(folder("/Volumes/Big", bytes: 900)))
        await settle()
        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big")

        work.emitPartial(0, result: result(folder("/Volumes/Old", bytes: 20)))
        await settle()

        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big",
                       "a withdrawn scan's snapshot repainted the ring as the volume")
        XCTAssertEqual(dvm.focusPath.first?.path, "/Volumes/Big",
                       "the focus collapsed onto a tree the screen was not showing")
        work.release(0, with: nil)
        work.release(0, with: nil)
        await settle()
    }

    /// A folder measurement wants its final tree and nothing on the way: asked
    /// for snapshots it would build one every third of a second for a ring that
    /// is not drawn from them. The control is the volume walk, which does ask.
    func testAFolderMeasurementAsksForNoUpdates() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)
        XCTAssertTrue(work.asksForUpdates(0), "control: the volume walk asks for updates")
        work.release(0, with: result(folder("/Volumes/Big", bytes: 900,
                                          children: [folder("/Volumes/Big/Sub", bytes: 20)])))
        await settle()

        dvm.drill(into: "/Volumes/Big/Sub")
        await untilParked(work, count: 1)

        XCTAssertFalse(work.asksForUpdates(0), "the folder measurement asked for updates")
        work.release(0, with: nil)
        await settle()
    }

    /// And its own scan's snapshots still arrive — the gate must not close the
    /// door it exists to keep open.
    func testTheShownScansPartialsStillDrawTheRing() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)

        work.emitPartial(0,
                         result: result(folder("/Volumes/Big", bytes: 100,
                                                  children: [folder("/Volumes/Big/One", bytes: 60)])))
        await settle()
        XCTAssertEqual(dvm.result?.root.children.count, 1)

        work.emitPartial(0,
                         result: result(folder("/Volumes/Big", bytes: 300,
                                                  children: [folder("/Volumes/Big/One", bytes: 60),
                                                             folder("/Volumes/Big/Two", bytes: 240)])))
        await settle()
        XCTAssertEqual(dvm.result?.root.children.count, 2, "the ring stopped growing")
        work.release(0, with: nil)
        await settle()
    }

    /// The gesture the whole tangle starts from: an arc at the rim of a tree
    /// that is still being walked. A folder with no children there is not "as
    /// deep as the scan went", it is "not walked yet" — and the walk that is
    /// running will bring it in. A second walk of the same folder competes with
    /// the first for the same disk and has its answer thrown away by the next
    /// snapshot.
    func testDrillingIntoAnUnwalkedFolderStartsNoSecondScanWhileTheFirstRuns() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)

        work.emitPartial(0,
                         result: result(folder("/Volumes/Big", bytes: 100,
                                                  children: [folder("/Volumes/Big/Rim", bytes: 60)])))
        await settle()
        XCTAssertTrue(dvm.live)

        dvm.drill(into: "/Volumes/Big/Rim")
        await settle()

        XCTAssertEqual(work.parkedCount, 1,
                       "a rim click started a second walk of the same volume")
        work.release(0, with: nil)
        await settle()
    }

    // MARK: - An answer to a withdrawn question

    /// "New scan" empties the screen and shows the volume picker. The scan that
    /// was already finishing must not put the discarded tree back.
    func testAResultArrivingAfterNewScanIsDiscarded() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)

        dvm.newScan()
        XCTAssertEqual(dvm.phase, .start)

        work.release(0, with: result(folder("/Volumes/Big", bytes: 900)))
        await settle()

        XCTAssertEqual(dvm.phase, .start, "the discarded scan replaced the volume picker")
        XCTAssertNil(dvm.result)
    }

    /// Stop is a withdrawal too, and the engine may already have finished by
    /// the time it is pressed — so cancelling is a no-op and the
    /// answer arrives anyway.
    func testAResultArrivingAfterStopIsDiscarded() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)

        dvm.cancel()
        XCTAssertEqual(dvm.phase, .start)

        work.release(0, with: result(folder("/Volumes/Big", bytes: 900)))
        await settle()

        XCTAssertEqual(dvm.phase, .start, "a stopped scan showed its result anyway")
        XCTAssertNil(dvm.result)
        XCTAssertFalse(dvm.live)
    }

    /// The ordinary path still works: nothing withdrawn, the result lands.
    func testAScanNobodyWithdrewShowsItsResult() async {
        let work = HeldWork()
        let dvm = model(work)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(work, count: 1)

        work.release(0, with: result(folder("/Volumes/Big", bytes: 900)))
        await settle()

        XCTAssertEqual(dvm.phase, .result)
        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big")
        XCTAssertFalse(dvm.live)
    }
}
