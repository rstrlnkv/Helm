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

    /// What the engine behind this wire does with a request.
    ///
    /// **A fake that can only answer is simpler than the port it stands for.**
    /// `EngineTransport.send` is declared `throws` and its only implementation
    /// answers empty `Data` for a handler whose engine has gone — which
    /// `DiskViewModel.shared(vm:)`'s own comment describes in as many words:
    /// a cached view model outliving its engine gets "every request with empty
    /// Data from then on", the state switching the module off and on produces.
    /// Without these two cases, «the removal nobody answered» was a state no
    /// test in this target could write down, whatever anybody wrote.
    ///
    /// Kept apart from each other rather than folded together: JSON decodes
    /// nothing from either, but they are not the same wire, and a command
    /// answering a raw payload would tell them apart.
    enum Answer: Equatable {
        /// The fixture's reply: an engine that is there and answers.
        case reply
        /// `send` throws, which `TransportClient.request` folds to the same nil
        /// as a reply that will not decode.
        case refuse
        /// Empty `Data` — an engine that is gone, or a command it does not know.
        case nothing
    }

    private let lock = NSLock()
    private var results: [String: ScanResult] = [:]
    private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
    private var answer: Answer = .reply
    private let volumes: [VolumeInfo]
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

    /// The engine going away under the page, or coming back. A port that can
    /// change while the app is running says so rather than being fixed at init
    /// (CLAUDE.md § Anything that can stop being true on its own).
    func answers(_ answer: Answer) {
        lock.lock(); self.answer = answer; lock.unlock()
    }

    private var currentAnswer: Answer {
        lock.lock(); defer { lock.unlock() }; return answer
    }

    /// What the engine was actually asked to trash. A basket row and a removal
    /// are not one to one — a cache row stands for its contents — so a test of
    /// that has to be able to read the request rather than the basket.
    var trashRequests: [[String]] {
        lock.lock(); defer { lock.unlock() }; return requestedTrash
    }
    private var requestedTrash: [[String]] = []

    private func noteTrash(_ paths: [String]) {
        lock.lock(); requestedTrash.append(paths); lock.unlock()
    }

    private func result(for path: String) -> ScanResult? {
        lock.lock(); defer { lock.unlock() }; return results[path]
    }

    private var currentRemoval: DiskRemoval {
        lock.lock(); defer { lock.unlock() }; return removal
    }

    func send(_ command: EngineCommand) async throws -> Data {
        // The request is recorded before the wire is consulted: a test of a
        // silence has to be able to assert that the batch really was sent, or it
        // is asserting an absence over a press that never happened.
        if command.name == DiskCommand.trash.rawValue {
            noteTrash((try? JSONDecoder().decode([String].self, from: command.payload)) ?? [])
        }
        switch currentAnswer {
        case .refuse: throw NoEngine.gone
        case .nothing: return Data()
        case .reply: break
        }
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

/// What a transport with nothing behind it throws.
enum NoEngine: Error { case gone }

// MARK: - Parks until released

/// Every "scan" parks until the test releases it and events are pushed by hand,
/// so the interleaving is chosen rather than raced — and a walk can be caught
/// in flight, which is the state the Stop button is visible in. A removal parks
/// too when the test asks for it (`holdTrash`), which is the state the basket
/// must not move in.
final class HeldTransport: EngineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Data, Never>] = []
    private var requests: [ScanRequest] = []
    private var trashBatches: [[String]] = []
    private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
    private var heldTrash: [CheckedContinuation<Data, Never>] = []
    private var holdsTrash = false
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
            noteTrash((try? JSONDecoder().decode([String].self, from: command.payload)) ?? [])
            guard isHoldingTrash else {
                return (try? JSONEncoder().encode(currentRemoval)) ?? Data()
            }
            return await withCheckedContinuation { parkTrash($0) }
        default:
            return Data()
        }
    }

    // Locking lives in non-async helpers: taking an NSLock across a suspension
    // point is what the compiler objects to, and it is right to.
    private func note(_ request: ScanRequest) {
        lock.lock(); requests.append(request); lock.unlock()
    }

    private func noteTrash(_ paths: [String]) {
        lock.lock(); trashBatches.append(paths); lock.unlock()
    }

    private func parkTrash(_ continuation: CheckedContinuation<Data, Never>) {
        lock.lock(); heldTrash.append(continuation); lock.unlock()
    }

    private var isHoldingTrash: Bool {
        lock.lock(); defer { lock.unlock() }; return holdsTrash
    }

    /// Hold the removal open until `releaseTrash()`.
    ///
    /// **A fake that answers a removal on the spot cannot express a removal that
    /// is running**, and everything the page does *during* one — the button that
    /// should be dim, the row that should not be tickable — is then a state no
    /// test could write down whatever anybody wrote. It is off by default
    /// because the other files here are about what the model holds afterwards,
    /// and a batch that never comes back would hang those instead of failing
    /// them.
    func holdTrash() {
        lock.lock(); holdsTrash = true; lock.unlock()
    }

    /// Every batch the engine was really handed, in order. A basket row and a
    /// removal are not one to one, and a second press sends a second batch:
    /// counting them is how a refusal is told from a silence.
    var trashRequests: [[String]] {
        lock.lock(); defer { lock.unlock() }; return trashBatches
    }

    func releaseTrash() {
        lock.lock()
        let waiting = heldTrash
        heldTrash = []
        let answer = removal
        lock.unlock()
        let payload = (try? JSONEncoder().encode(answer)) ?? Data()
        waiting.forEach { $0.resume(returning: payload) }
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

/// The same wait for a removal: it has left the model and is suspended inside
/// the transport, which is the only moment «while a removal runs» exists in.
@MainActor
func untilTrashing(_ transport: HeldTransport, count: Int = 1) async {
    for _ in 0..<1000 where transport.trashRequests.count < count { await Task.yield() }
}

/// Room for the tasks already scheduled to land. The two copies of this yielded
/// 20 times and 50; the longer one is kept, because every use is either waiting
/// for something to appear or asserting that it did not, and both are stronger
/// the longer they wait.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}
