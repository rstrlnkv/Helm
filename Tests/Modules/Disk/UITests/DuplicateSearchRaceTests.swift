import XCTest
import HelmContract
import HelmUI
import Module_Disk_Engine
@testable import Module_Disk_UI

/// The duplicate search against the one order of events nobody drew: the
/// answer that arrives after the question was withdrawn.
///
/// The trap `duplicateGeneration` exists to close: `cancelDuplicates` flips
/// `duplicatesRunning` off locally and asks the engine to stop — but the
/// request task keeps awaiting, and without the generation check whatever
/// the transport eventually returned was written straight into `duplicates`.
/// A cancelled search's late result resurfaced as if the user had asked; and
/// if a second search was already running by then, the first one's corpse
/// overwrote `duplicates` with the wrong folder's groups and cleared
/// `duplicatesRunning` while the second was still in flight.
///
/// The transport here is a hand-cranked fake: "duplicates" requests suspend
/// until the test releases them, so the interleaving is chosen, not raced —
/// the assertions hold for an order of events, never for a lucky delay.
@MainActor
final class DuplicateSearchRaceTests: XCTestCase {

    // MARK: - The hand-cranked transport

    /// Answers "scan" instantly with a fixed tree and parks every
    /// "duplicates" request until the test releases it, in the order the test
    /// chooses.
    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var held: [CheckedContinuation<Data, Never>] = []

        var pendingDuplicates: Int {
            lock.lock(); defer { lock.unlock() }
            return held.count
        }

        /// Releases the oldest parked "duplicates" request with these groups.
        func release(with groups: [DuplicateGroup]) {
            lock.lock()
            let next = held.isEmpty ? nil : held.removeFirst()
            lock.unlock()
            next?.resume(returning: (try? JSONEncoder().encode(groups)) ?? Data())
        }

        let events = AsyncStream<EngineEvent> { _ in }

        func send(_ command: EngineCommand) async throws -> Data {
            switch command.name {
            case "scan":
                let root = DiskEntry(name: "fake", path: "/fake", bytes: 10,
                                     isDirectory: true, noAccess: false, children: [])
                let result = ScanResult(root: root, freeBytes: 0,
                                        filesScanned: 1, seconds: 0, advice: [])
                return (try? JSONEncoder().encode(result)) ?? Data()
            case "duplicates":
                return await withCheckedContinuation { continuation in
                    lock.lock(); held.append(continuation); lock.unlock()
                }
            default:
                return Data()
            }
        }
    }

    private var transport: HeldTransport!
    private var dvm: DiskViewModel!
    /// The user's real last-scan cache, put back exactly as found: the view
    /// model's store is not injectable, and a test must not leave a fake tree
    /// where somebody's minute-long measurement was.
    private var savedCache: Data?
    private let cacheURL = ScanStore().fileURL

    override func setUp() async throws {
        savedCache = try? Data(contentsOf: cacheURL)
        transport = HeldTransport()
        dvm = DiskViewModel(vm: ModuleViewModel(transport: transport))
        // A scan through the fake gives the view model a focus; without one
        // `findDuplicates` refuses to start.
        await dvm.scan(path: "/fake")
        XCTAssertNotNil(dvm.focus)
    }

    override func tearDown() async throws {
        // `scan` saves its result detached; outwait it, then restore.
        try? await Task.sleep(nanoseconds: 400_000_000)
        if let savedCache {
            try? savedCache.write(to: cacheURL, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: cacheURL)
        }
    }

    /// Yields until `condition` holds or the budget runs out. The budget is a
    /// ceiling for the fixed case, never the proof — every assertion below is
    /// made on state, after the interleaving has been fully driven.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func groups(_ paths: [String]) -> [DuplicateGroup] {
        [DuplicateGroup(bytes: 2_000_000, paths: paths)]
    }

    // MARK: - The races

    /// Cancel, then the answer arrives anyway. The sheet closed on nil; the
    /// late result must not resurface as a claim the user never asked to see.
    func testACancelledSearchsLateResultDoesNotResurface() async {
        dvm.findDuplicates()
        await settle { transport.pendingDuplicates == 1 }
        XCTAssertEqual(transport.pendingDuplicates, 1)

        dvm.cancelDuplicates()
        XCTAssertFalse(dvm.duplicatesRunning)

        // The engine finished the walk before the cancel reached it and
        // answered with real groups.
        transport.release(with: groups(["/fake/a", "/fake/b"]))
        await settle { dvm.duplicates != nil }

        XCTAssertNil(dvm.duplicates,
                     "a search cancelled by the user delivered its result anyway")
    }

    /// Cancel, start a second search, and then the first one's answer lands.
    /// The stale result must neither pose as the second search's answer nor
    /// clear its running flag.
    func testAStaleResultDoesNotClobberTheSecondSearch() async {
        dvm.findDuplicates()
        await settle { transport.pendingDuplicates == 1 }
        dvm.cancelDuplicates()

        dvm.findDuplicates()
        await settle { transport.pendingDuplicates == 2 }
        XCTAssertEqual(transport.pendingDuplicates, 2)
        XCTAssertTrue(dvm.duplicatesRunning)

        // The first search's answer arrives while the second is in flight.
        transport.release(with: groups(["/stale/a", "/stale/b"]))
        await settle { !dvm.duplicatesRunning || dvm.duplicates != nil }

        XCTAssertTrue(dvm.duplicatesRunning,
                      "the cancelled search's corpse cleared the running flag "
                      + "of the search that replaced it")
        XCTAssertNil(dvm.duplicates,
                     "the cancelled search's groups posed as the new search's answer")

        // The second search's own answer still lands as the answer.
        let fresh = groups(["/fresh/a", "/fresh/b"])
        transport.release(with: fresh)
        await settle { dvm.duplicates != nil }
        XCTAssertEqual(dvm.duplicates, fresh)
        XCTAssertFalse(dvm.duplicatesRunning)
    }
}
