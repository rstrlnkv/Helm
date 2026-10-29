import Foundation
import HelmContract
import HelmRuntime
import Module_Disk_Engine
import XCTest
@testable import Module_Disk_UI

// The two engines this module's page tests are written against, and the waits
// that go with them.
//
// **They are two on purpose.** `AnsweringWork` answers on the spot;
// `HeldWork` parks every scan until a test releases it. A fake that answers
// synchronously releases a gate before the call it is gating returns,
// so a test of a busy gate passes with the gate deleted — which is why
// `DiskScanRaceTests` and `StopKeepsWhatItMeasuredTests` need the parking one
// and cannot be served by the immediate one. Merging them would take the
// mid-walk state out of the language these tests are written in.

// MARK: - Answers on the spot

/// Volumes, scans and removals, all returned without suspending. For tests
/// about what the view model *keeps* across a transition rather than about
/// interleaving.
final class AnsweringWork: DiskWork, @unchecked Sendable {

    private let lock = NSLock()
    private var results: [String: ScanResult] = [:]
    private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
    private let volumes: [VolumeInfo]

    init(volumes: [VolumeInfo]) {
        self.volumes = volumes
    }

    func answer(_ path: String, with result: ScanResult) {
        lock.lock(); results[path] = result; lock.unlock()
    }

    func answerTrash(with removal: DiskRemoval) {
        lock.lock(); self.removal = removal; lock.unlock()
    }

    /// What the engine was actually asked to trash. A basket row and a removal
    /// are not one to one — a cache row stands for its contents — so a test of
    /// that has to be able to read the request rather than the basket.
    var trashRequests: [[String]] {
        lock.lock(); defer { lock.unlock() }; return requestedTrash
    }
    private var requestedTrash: [[String]] = []

    func mountedVolumes() async -> [VolumeInfo] { volumes }

    func scan(path: String, unattended: Bool,
              updates: (@Sendable (DiskScanUpdate) -> Void)?) async -> ScanResult? {
        result(for: path)
    }

    func cancel() {}

    func trash(_ paths: [String]) async -> DiskRemoval {
        noteTrash(paths)
    }

    // Locking lives in non-async helpers: taking an NSLock across a suspension
    // point is what the compiler objects to, and it is right to.
    private func result(for path: String) -> ScanResult? {
        lock.lock(); defer { lock.unlock() }; return results[path]
    }

    private func noteTrash(_ paths: [String]) -> DiskRemoval {
        lock.lock(); defer { lock.unlock() }
        requestedTrash.append(paths)
        return removal
    }

    func backgroundScan() async -> ScanReport? { nil }
}

// MARK: - Parks until released

/// Every scan parks until the test releases it and updates are pushed by hand,
/// so the interleaving is chosen rather than raced — and a walk can be caught
/// in flight, which is the state the Stop button is visible in. A removal parks
/// too when the test asks for it (`holdTrash`), which is the state the basket
/// must not move in.
final class HeldWork: DiskWork, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<ScanResult?, Never>] = []
    private var sinks: [(@Sendable (DiskScanUpdate) -> Void)?] = []
    private var trashBatches: [[String]] = []
    private var removal = DiskRemoval(removed: [], refused: [], freedBytes: 0)
    private var heldTrash: [CheckedContinuation<DiskRemoval, Never>] = []
    private var holdsTrash = false

    func mountedVolumes() async -> [VolumeInfo] { [] }

    func scan(path: String, unattended: Bool,
              updates: (@Sendable (DiskScanUpdate) -> Void)?) async -> ScanResult? {
        await withCheckedContinuation { park($0, updates) }
    }

    func cancel() {}

    func backgroundScan() async -> ScanReport? { nil }

    func trash(_ paths: [String]) async -> DiskRemoval {
        noteTrash(paths)
        guard isHoldingTrash else { return currentRemoval }
        return await withCheckedContinuation { parkTrash($0) }
    }

    // Locking lives in non-async helpers: taking an NSLock across a suspension
    // point is what the compiler objects to, and it is right to.
    private func noteTrash(_ paths: [String]) {
        lock.lock(); trashBatches.append(paths); lock.unlock()
    }

    private func parkTrash(_ continuation: CheckedContinuation<DiskRemoval, Never>) {
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
        waiting.forEach { $0.resume(returning: answer) }
    }

    private func park(_ continuation: CheckedContinuation<ScanResult?, Never>,
                      _ updates: (@Sendable (DiskScanUpdate) -> Void)?) {
        lock.lock(); parked.append(continuation); sinks.append(updates); lock.unlock()
    }

    private var currentRemoval: DiskRemoval {
        lock.lock(); defer { lock.unlock() }; return removal
    }

    func answerTrash(with removal: DiskRemoval) {
        lock.lock(); self.removal = removal; lock.unlock()
    }

    var parkedCount: Int { lock.lock(); defer { lock.unlock() }; return parked.count }

    /// Whether the scan at `index` was started with a sink for its updates. The
    /// volume walk draws a ring and asks for them; the measurement of one folder
    /// wants only its final tree and asks for none.
    func asksForUpdates(_ index: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return sinks.indices.contains(index) && sinks[index] != nil
    }

    func release(_ index: Int, with result: ScanResult?) {
        lock.lock()
        guard parked.indices.contains(index) else { lock.unlock(); return }
        let continuation = parked.remove(at: index)
        sinks.remove(at: index)
        lock.unlock()
        continuation.resume(returning: result)
    }

    /// A snapshot from the scan at `index`, through the sink that scan was given.
    func emitPartial(_ index: Int, result: ScanResult) {
        lock.lock()
        let sink = sinks.indices.contains(index) ? sinks[index] : nil
        lock.unlock()
        sink?(.partial(result))
    }
}

// MARK: - Fixtures and waits

/// A directory, named after its path, with what it weighs.
func folder(_ path: String, bytes: Int, children: [DiskEntry] = []) -> DiskEntry {
    DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
              isDirectory: true, noAccess: false, children: children)
}

/// Waits for the scan to park inside `HeldWork`. Yielding a fixed number
/// of times is a guess about scheduling; this is the condition the test
/// depends on.
///
/// `@MainActor`, as every caller is: the yields have to run where the view
/// model's own tasks run, or the wait hops off and measures another thread.
@MainActor
func untilParked(_ work: HeldWork, count: Int) async {
    for _ in 0..<1000 where work.parkedCount < count { await Task.yield() }
}

/// The same wait for a removal: it has left the model and is suspended inside
/// `HeldWork.trash`, which is the only moment «while a removal runs» exists in.
@MainActor
func untilTrashing(_ work: HeldWork, count: Int = 1) async {
    for _ in 0..<1000 where work.trashRequests.count < count { await Task.yield() }
}

/// Room for the tasks already scheduled to land. The two copies of this yielded
/// 20 times and 50; the longer one is kept, because every use is either waiting
/// for something to appear or asserting that it did not, and both are stronger
/// the longer they wait.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}
