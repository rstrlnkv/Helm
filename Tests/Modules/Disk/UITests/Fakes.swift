import Foundation
import HelmContract
import HelmRuntime
import Module_Disk_Engine
import XCTest

/// The two transports this module's page tests are written against, and the
/// waits that go with them.
///
/// **They are two on purpose.** `AnsweringTransport` answers on the spot;
/// `HeldTransport` parks every scan until a test releases it. A fake that
/// answers synchronously releases a gate before the call it is gating returns,
/// so a test of a busy gate passes with the gate deleted — which is why
/// `DiskScanRaceTests` and `StopKeepsWhatItMeasuredTests` need the parking one
/// and cannot be served by the immediate one. Merging them would take the
/// mid-walk state out of the language these tests are written in.
///
/// Each was spelled twice before it moved here, and the copies had drifted: one
/// `HeldTransport` had grown a "trash" case the other had not. The union is
/// kept — a fake simpler than the thing it stands for cannot fail the way the
/// thing can.

// MARK: - Answers on the spot

/// Volumes, scans and removals, all returned without suspending. For tests
/// about what the view model *keeps* across a transition rather than about
/// interleaving.
final class AnsweringTransport: EngineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [String: ScanResult] = [:]
    private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
    let volumes: [VolumeInfo]
    let events: AsyncStream<EngineEvent>

    init(volumes: [VolumeInfo]) {
        self.volumes = volumes
        events = AsyncStream { _ in }
    }

    func answer(_ path: String, with result: ScanResult) {
        lock.lock(); results[path] = result; lock.unlock()
    }

    func answerTrash(with removal: DiskRemoval) {
        lock.lock(); self.removal = removal; lock.unlock()
    }

    private func result(for path: String) -> ScanResult? {
        lock.lock(); defer { lock.unlock() }; return results[path]
    }

    private var currentRemoval: DiskRemoval {
        lock.lock(); defer { lock.unlock() }; return removal
    }

    func send(_ command: EngineCommand) async throws -> Data {
        switch command.name {
        case "volumes":
            return (try? JSONEncoder().encode(volumes)) ?? Data()
        case "scan":
            let request = try? JSONDecoder().decode(ScanRequest.self, from: command.payload)
            return (try? JSONEncoder().encode(request.flatMap { result(for: $0.path) })) ?? Data()
        case "trash":
            return (try? JSONEncoder().encode(currentRemoval)) ?? Data()
        default:
            return Data()
        }
    }
}

// MARK: - Parks until released

/// Every "scan" parks until the test releases it and events are pushed by hand,
/// so the interleaving is chosen rather than raced — and a walk can be caught
/// in flight, which is the state the Stop button is visible in.
final class HeldTransport: EngineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Data, Never>] = []
    private var requests: [ScanRequest] = []
    private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
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
        case "trash":
            return (try? JSONEncoder().encode(currentRemoval)) ?? Data()
        default:
            return Data()
        }
    }

    // Locking lives in non-async helpers: taking an NSLock across a suspension
    // point is what the compiler objects to, and it is right to.
    private func note(_ request: ScanRequest) {
        lock.lock(); requests.append(request); lock.unlock()
    }

    private func park(_ continuation: CheckedContinuation<Data, Never>) {
        lock.lock(); parked.append(continuation); lock.unlock()
    }

    private var currentRemoval: DiskRemoval {
        lock.lock(); defer { lock.unlock() }; return removal
    }

    func answerTrash(with removal: DiskRemoval) {
        lock.lock(); self.removal = removal; lock.unlock()
    }

    var parkedCount: Int { lock.lock(); defer { lock.unlock() }; return parked.count }

    /// The name the view model gave the request at `index` — the screen has to
    /// be able to recognise its own scan's events.
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

// MARK: - Fixtures and waits

/// A directory, named after its path, with what it weighs.
func folder(_ path: String, bytes: Int, children: [DiskEntry] = []) -> DiskEntry {
    DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
              isDirectory: true, noAccess: false, children: children)
}

/// Waits for the request task to reach the transport. Yielding a fixed number
/// of times is a guess about scheduling; this is the condition the test
/// depends on.
///
/// `@MainActor`, as every caller is: the yields have to run where the view
/// model's own tasks run, or the wait hops off and measures another thread.
@MainActor
func untilParked(_ transport: HeldTransport, count: Int) async {
    for _ in 0..<1000 where transport.parkedCount < count { await Task.yield() }
}

/// Room for the tasks already scheduled to land. The two copies of this yielded
/// 20 times and 50; the longer one is kept, because every use is either waiting
/// for something to appear or asserting that it did not, and both are stronger
/// the longer they wait.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}
