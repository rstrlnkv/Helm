import Foundation
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The transports this module's page tests are written against, and the store
/// and waits that go with them.
///
/// **There are two kinds on purpose.** `OneAnswerTransport` answers on the
/// spot; `HeldTransport` parks every "find" until a test releases it. A fake
/// that answers synchronously is over before the code under test is reached, so
/// nothing about a search *in flight* — a cancellation, an older answer landing
/// after a newer one, a page that goes away mid-search — can be written down
/// against it. Merging the two would make `DuplicateSearchRaceTests` and
/// `SharedViewModelTests` vacuous rather than shorter.
///
/// Each was spelled twice before it moved here. The one difference between the
/// two `HeldTransport`s was a list of the command names it had been sent, which
/// no test in this target ever read — a recorder nobody reads is not richer
/// behaviour, so it did not survive the merge.

// MARK: - Answers on the spot

/// Returns the same groups to every "find" and nothing to anything else.
final class OneAnswerTransport: EngineTransport, @unchecked Sendable {
    private let groups: [DuplicateGroup]
    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    init(groups: [DuplicateGroup]) { self.groups = groups }

    func send(_ command: EngineCommand) async throws -> Data {
        guard command.name == "find" else { return Data() }
        return (try? JSONEncoder().encode(groups)) ?? Data()
    }
}

// MARK: - Parks until released

/// Parks every "find" until the test releases it, so the interleaving is chosen
/// rather than raced. An assertion that holds only for a lucky delay is not a
/// test.
final class HeldTransport: EngineTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var parked: [CheckedContinuation<Data, Never>] = []

    var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

    func send(_ command: EngineCommand) async throws -> Data {
        guard command.name == "find" else { return Data() }
        return await withCheckedContinuation { park($0) }
    }

    // Locking lives in a non-async helper: taking an NSLock across a suspension
    // point is what the compiler is objecting to, and it is right to.
    private func park(_ continuation: CheckedContinuation<Data, Never>) {
        lock.lock(); parked.append(continuation); lock.unlock()
    }

    var parkedCount: Int { lock.lock(); defer { lock.unlock() }; return parked.count }

    /// Releases the request parked at `index` with a group named after `folder`,
    /// so a test can tell whose answer landed.
    func release(_ index: Int, folder: String) {
        lock.lock()
        guard parked.indices.contains(index) else { lock.unlock(); return }
        let continuation = parked.remove(at: index)
        lock.unlock()
        let group = DuplicateGroup(bytes: 1_000_000,
                                   paths: ["/\(folder)/a", "/\(folder)/b"])
        continuation.resume(returning: (try? JSONEncoder().encode([group])) ?? Data())
    }
}

// MARK: - Fixtures and waits

/// Fixtures live under the home directory because `UserFileScope` judges the
/// real path, and one in `/tmp` would be refused for the wrong reason.
var home: String { NSHomeDirectory() }

/// **In memory, never `UserDefaults.standard`.** The real store is the person's
/// remembered folder; the runner's domain is `com.apple.dt.xctest.tool`, shared
/// with every package tested on this machine, and 3028 keys had accumulated
/// there before these tests stopped writing to it.
///
/// The default folder is one nothing walks: a search that parks never reaches
/// it, so only the fixtures that let a search finish name a real path.
func duplicatesStore(folder: String = "/some/folder") -> NamespacedStore {
    let store = NamespacedStore(namespace: "duplicates", backing: InMemoryKeyValueStore())
    store.set(folder, for: "folder")
    return store
}

/// A view model that has already searched, with `groups` as the answer.
@MainActor
func searchedModel(_ groups: [DuplicateGroup]) async -> DuplicatesViewModel {
    let dvm = DuplicatesViewModel(vm: ModuleViewModel(transport:
        OneAnswerTransport(groups: groups)), store: duplicatesStore(folder: "\(home)/Downloads"))
    dvm.search()
    for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
    return dvm
}

/// A view model whose searches will park, for the tests about a search in
/// flight.
@MainActor
func heldModel(_ transport: HeldTransport) -> DuplicatesViewModel {
    DuplicatesViewModel(vm: ModuleViewModel(transport: transport),
                        store: duplicatesStore())
}

/// Room for the tasks already scheduled to land. Spelled three times in
/// `DuplicateSearchRaceTests` as twenty yields; fifty, because every use is
/// either waiting for something to appear or asserting that it did not, and
/// both are stronger the longer they wait.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

/// Waits for the request tasks to actually reach the transport. Yielding a
/// fixed number of times is a guess about scheduling; this is the condition the
/// test depends on.
@MainActor
func untilParked(_ transport: HeldTransport, count: Int) async {
    for _ in 0..<1000 where transport.parkedCount < count { await Task.yield() }
}
