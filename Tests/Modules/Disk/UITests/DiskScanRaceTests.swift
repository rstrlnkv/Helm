import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The two orders of events the ring never survived: a snapshot from a scan the
/// screen is not showing, and an answer to a scan the user has already
/// withdrawn.
///
/// Both are reachable through one gesture. Drilling into a folder the walk has
/// not reached yet issues a *second* "scan" command while the first is still
/// walking, and drilling is not gated on `live` — so from the moment the first
/// partial draws the ring, a click on its rim starts a scan whose events
/// travelled the same transport as the volume's, wearing no name.
///
/// The transport is hand-cranked: every "scan" parks until the test releases
/// it, and events are pushed by hand, so the interleaving is chosen rather than
/// raced.
@MainActor
final class DiskScanRaceTests: XCTestCase {

    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var parked: [CheckedContinuation<Data, Never>] = []
        private var requests: [ScanRequest] = []
        private var continuation: AsyncStream<EngineEvent>.Continuation?
        let events: AsyncStream<EngineEvent>

        init() {
            var handle: AsyncStream<EngineEvent>.Continuation?
            events = AsyncStream { handle = $0 }
            continuation = handle
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch command.name {
            case "volumes":
                return (try? JSONEncoder().encode([VolumeInfo]())) ?? Data()
            case "scan":
                if let request = try? JSONDecoder().decode(ScanRequest.self,
                                                           from: command.payload) {
                    note(request)
                }
                return await withCheckedContinuation { park($0) }
            default:
                return Data()
            }
        }

        // Locking lives in non-async helpers: taking an NSLock across a
        // suspension point is what the compiler objects to, and it is right to.
        private func note(_ request: ScanRequest) {
            lock.lock(); requests.append(request); lock.unlock()
        }

        private func park(_ continuation: CheckedContinuation<Data, Never>) {
            lock.lock(); parked.append(continuation); lock.unlock()
        }

        var parkedCount: Int { lock.lock(); defer { lock.unlock() }; return parked.count }

        /// The name the view model gave the request at `index` — the whole
        /// point of the change: the screen has to be able to recognise its own
        /// scan's events.
        func scanID(_ index: Int) -> Int {
            lock.lock(); defer { lock.unlock() }
            return requests.indices.contains(index) ? requests[index].scan : -1
        }

        func release(_ index: Int, with result: ScanResult?) {
            lock.lock()
            guard parked.indices.contains(index) else { lock.unlock(); return }
            let continuation = parked.remove(at: index)
            lock.unlock()
            continuation.resume(returning: (try? JSONEncoder().encode(result)) ?? Data())
        }

        func emitPartial(scan: Int, result: ScanResult) {
            let payload = (try? JSONEncoder().encode(PartialScan(scan: scan, result: result)))
                ?? Data()
            continuation?.yield(EngineEvent(name: "partial", payload: payload))
        }
    }

    // MARK: - Fixtures

    private func tree(_ path: String, bytes: Int, children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                  isDirectory: true, noAccess: false, children: children)
    }

    private func result(_ root: DiskEntry, freeBytes: Int = 500) -> ScanResult {
        ScanResult(root: root, freeBytes: freeBytes, filesScanned: 10, seconds: 1)
    }

    private func model(_ transport: HeldTransport) -> DiskViewModel {
        // A store of its own: the module's real one is the user's last scan.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-disk-race-\(UUID().uuidString)")
        return DiskViewModel(vm: ModuleViewModel(transport: transport),
                             store: ScanStore(directory: directory))
    }

    /// Waits for the request task to reach the transport. Yielding a fixed
    /// number of times is a guess about scheduling; this is the condition the
    /// test depends on.
    private func untilParked(_ transport: HeldTransport, count: Int) async {
        for _ in 0..<1000 where transport.parkedCount < count { await Task.yield() }
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: - A snapshot belongs to one scan

    /// The volume is on screen; a folder measurement's snapshot must not take
    /// the ring over.
    func testAPartialFromAnotherScanDoesNotRepaintTheRing() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        let volume = transport.scanID(0)
        transport.emitPartial(scan: volume, result: result(tree("/Volumes/Big", bytes: 900)))
        await settle()
        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big")

        // A second scan, of a folder inside it, with a name of its own.
        transport.emitPartial(scan: volume + 1,
                              result: result(tree("/Volumes/Big/Sub", bytes: 20)))
        await settle()

        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big",
                       "a folder measurement's snapshot repainted the ring as the volume")
        XCTAssertEqual(dvm.focusPath.first?.path, "/Volumes/Big",
                       "the focus collapsed onto a tree the screen was not showing")
        transport.release(0, with: nil)
        await settle()
    }

    /// And its own scan's snapshots still arrive — the gate must not close the
    /// door it exists to keep open.
    func testTheShownScansPartialsStillDrawTheRing() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        let volume = transport.scanID(0)
        transport.emitPartial(scan: volume,
                              result: result(tree("/Volumes/Big", bytes: 100,
                                                  children: [tree("/Volumes/Big/One", bytes: 60)])))
        await settle()
        XCTAssertEqual(dvm.result?.root.children.count, 1)

        transport.emitPartial(scan: volume,
                              result: result(tree("/Volumes/Big", bytes: 300,
                                                  children: [tree("/Volumes/Big/One", bytes: 60),
                                                             tree("/Volumes/Big/Two", bytes: 240)])))
        await settle()
        XCTAssertEqual(dvm.result?.root.children.count, 2, "the ring stopped growing")
        transport.release(0, with: nil)
        await settle()
    }

    /// The gesture the whole tangle starts from: an arc at the rim of a tree
    /// that is still being walked. A folder with no children there is not "as
    /// deep as the scan went", it is "not walked yet" — and the walk that is
    /// running will bring it in. A second walk of the same folder competes with
    /// the first for the same disk and has its answer thrown away by the next
    /// snapshot.
    func testDrillingIntoAnUnwalkedFolderStartsNoSecondScanWhileTheFirstRuns() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        transport.emitPartial(scan: transport.scanID(0),
                              result: result(tree("/Volumes/Big", bytes: 100,
                                                  children: [tree("/Volumes/Big/Rim", bytes: 60)])))
        await settle()
        XCTAssertTrue(dvm.live)

        dvm.drill(into: "/Volumes/Big/Rim")
        await settle()

        XCTAssertEqual(transport.parkedCount, 1,
                       "a rim click started a second walk of the same volume")
        transport.release(0, with: nil)
        await settle()
    }

    // MARK: - An answer to a withdrawn question

    /// "New scan" empties the screen and shows the volume picker. The scan that
    /// was already finishing must not put the discarded tree back.
    func testAResultArrivingAfterNewScanIsDiscarded() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        dvm.newScan()
        XCTAssertEqual(dvm.phase, .start)

        transport.release(0, with: result(tree("/Volumes/Big", bytes: 900)))
        await settle()

        XCTAssertEqual(dvm.phase, .start, "the discarded scan replaced the volume picker")
        XCTAssertNil(dvm.result)
    }

    /// Stop is a withdrawal too, and the engine may already have finished by
    /// the time it is pressed — so the "cancel" command is a no-op and the
    /// answer arrives anyway.
    func testAResultArrivingAfterStopIsDiscarded() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        dvm.cancel()
        XCTAssertEqual(dvm.phase, .start)

        transport.release(0, with: result(tree("/Volumes/Big", bytes: 900)))
        await settle()

        XCTAssertEqual(dvm.phase, .start, "a stopped scan showed its result anyway")
        XCTAssertNil(dvm.result)
        XCTAssertFalse(dvm.live)
    }

    /// The ordinary path still works: nothing withdrawn, the result lands.
    func testAScanNobodyWithdrewShowsItsResult() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        Task { await dvm.scan(path: "/Volumes/Big") }
        await untilParked(transport, count: 1)

        transport.release(0, with: result(tree("/Volumes/Big", bytes: 900)))
        await settle()

        XCTAssertEqual(dvm.phase, .result)
        XCTAssertEqual(dvm.result?.root.path, "/Volumes/Big")
        XCTAssertFalse(dvm.live)
    }
}
