import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The one order of events nobody draws: the answer that arrives after the
/// question was withdrawn.
///
/// `cancel()` stops the engine and puts the page back, but the request task is
/// still awaiting — and without the generation check whatever the transport
/// eventually returned was written straight into `groups`. A cancelled search
/// resurfaced as if it had been asked for; and with a second search already
/// running, the first one's corpse overwrote the newer folder's results.
///
/// The transport is hand-cranked: every "find" parks until the test releases
/// it, so the interleaving is chosen rather than raced. An assertion that
/// holds only for a lucky delay is not a test.
@MainActor
final class DuplicateSearchRaceTests: XCTestCase {

    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var parked: [CheckedContinuation<Data, Never>] = []
        private(set) var received: [String] = []

        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }

        func send(_ command: EngineCommand) async throws -> Data {
            note(command.name)
            guard command.name == "find" else { return Data() }
            return await withCheckedContinuation { continuation in
                park(continuation)
            }
        }

        // Locking lives in non-async helpers: taking an NSLock across a
        // suspension point is what the compiler is objecting to, and it is
        // right to.
        private func note(_ name: String) {
            lock.lock(); received.append(name); lock.unlock()
        }

        private func park(_ continuation: CheckedContinuation<Data, Never>) {
            lock.lock(); parked.append(continuation); lock.unlock()
        }

        var parkedCount: Int { lock.lock(); defer { lock.unlock() }; return parked.count }

        /// Releases the request parked at `index` with a named group.
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

    /// **In memory, never `UserDefaults.standard`** — the rule
    /// `ListsAgreeWithTheTreeTests` states and this test broke in the way that
    /// costs most: a fresh UUID namespace per call means the same key is never
    /// overwritten, so every invocation left one behind for good.
    ///
    /// `UserDefaults.standard` inside a test process is not Helm's domain, it
    /// is `com.apple.dt.xctest.tool` — the runner's own, shared with every
    /// package tested on the machine. Measured on this one before the fix:
    /// **3028 keys named `module.test.duplicates.<uuid>.folder`, 288 KB**, none
    /// of which anything would ever read again. The house rule is that a
    /// harness leaves nothing behind, and a fresh in-memory store is isolated
    /// by construction, which is what the UUID was reaching for.
    private func model(_ transport: HeldTransport) -> DuplicatesViewModel {
        let store = NamespacedStore(namespace: "test.duplicates",
                                    backing: InMemoryKeyValueStore())
        store.set("/some/folder", for: "folder")
        return DuplicatesViewModel(vm: ModuleViewModel(transport: transport), store: store)
    }

    /// Waits for the request tasks to actually reach the transport. Yielding a
    /// fixed number of times is a guess about scheduling; this is the condition
    /// the test actually depends on.
    private func untilParked(_ transport: HeldTransport, count: Int) async {
        for _ in 0..<1000 where transport.parkedCount < count { await Task.yield() }
    }

    /// A cancelled search's answer must not arrive as though it had been asked
    /// for. Cancel is a withdrawal, not a pause.
    func testALateAnswerToACancelledSearchIsDiscarded() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        dvm.search()
        await untilParked(transport, count: 1)
        XCTAssertEqual(dvm.phase, .searching)

        dvm.cancel()
        XCTAssertEqual(dvm.phase, .start)

        transport.release(0, folder: "withdrawn")
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(dvm.groups.isEmpty, "a withdrawn search wrote its answer anyway")
        XCTAssertEqual(dvm.phase, .start)
    }

    /// Two searches in flight: the older one finishing last must not overwrite
    /// the newer one's folder.
    func testTheOlderSearchCannotOverwriteTheNewer() async {
        let transport = HeldTransport()
        let dvm = model(transport)
        dvm.search()
        await untilParked(transport, count: 1)
        dvm.cancel()
        dvm.search()
        await untilParked(transport, count: 2)
        XCTAssertEqual(transport.parkedCount, 2, "both requests should be in flight")

        // The newer one answers first, then the older one arrives late.
        transport.release(1, folder: "newer")
        for _ in 0..<20 { await Task.yield() }
        transport.release(0, folder: "older")
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(dvm.groups.count, 1)
        XCTAssertTrue(dvm.groups[0].paths.allSatisfy { $0.contains("newer") },
                      "the older search overwrote the newer: \(dvm.groups[0].paths)")
    }
}
