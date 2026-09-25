import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **A word dropped from the queue must not go on claiming the section.**
///
/// `ask(_:)`'s queue branch sets `searchedQuery`/`searchReading` to `.waiting`
/// before a chain for the queued word exists at all — that is what makes
/// "Searching…" name the word that will actually be asked next rather than
/// the one still in flight (`ask`'s own doc comment). When the chain in front
/// of it finishes and the field no longer holds that word, the dequeue step
/// used to leave both fields exactly where queuing had put them: the section
/// went on reading `.searching` for a question nobody was ever going to put,
/// `ownListShowsNothing` refused to schedule a new pause for the same word
/// (`q != searchedQuery` read false), and `searchNow` refused it too
/// (`.waiting`). The only way out was erasing the field — coming back to the
/// same word left it stuck.
@MainActor
final class ADroppedQueuedWordStopsClaimingTheSectionTests: XCTestCase {

    /// A transport that holds each search until the test releases it, by
    /// query — the same shape `AStaleSearchDoesNotLandOnANewerOneTests` uses,
    /// and for the same reason: an instant fake could never have two chains
    /// out at once, which is the whole state this file is about.
    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let lock = NSLock()
        private var _asked: [String] = []
        var asked: [String] { lock.withLock { _asked } }

        private var gates: [String: DispatchSemaphore] = [:]
        private func gate(for query: String) -> DispatchSemaphore {
            lock.withLock {
                if let existing = gates[query] { return existing }
                let made = DispatchSemaphore(value: 0)
                gates[query] = made
                return made
            }
        }
        func release(_ query: String) { gate(for: query).signal() }

        /// **The teardown door.** "zzbb" is asked and never released by the
        /// test body on purpose — that is the state the case reads — which
        /// used to leave a `DispatchQueue.global()` thread parked in
        /// `gate.wait()` for the rest of the test *process*, not merely this
        /// test: nothing here ever signalled it. `open` makes every request
        /// from this call on skip the wait outright — belt and braces for a
        /// call arriving after teardown has already started closing this
        /// fixture down — and every gate already handed out is signalled
        /// once. One signal per gate is enough here, and not a promise this
        /// class makes in general: every query in this file parks at most
        /// once, so one gate never holds more than one waiting thread: the
        /// caller does not rely on that alone, either — `parked`, incremented
        /// and decremented around the same wait, is what `tearDown` actually
        /// asserts back down to zero.
        private var open = false
        private var parked = 0
        var parkedCount: Int { lock.withLock { parked } }
        func releaseAll() {
            lock.withLock {
                open = true
                gates.values.forEach { $0.signal() }
            }
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled:
                return try JSONEncoder().encode(
                    [BrewPackage(name: "wget", version: "1.25.0", isCask: false)])
            case .outdated:
                return try JSONEncoder().encode([OutdatedPackage]())
            case .descriptions:
                return try JSONEncoder().encode([String: String]())
            case .search:
                let query = String(data: command.payload, encoding: .utf8) ?? ""
                lock.withLock { _asked.append(query) }
                // The check, the gate's own creation and the count all in one
                // critical section — `releaseAll()` signals every gate that
                // exists *when it runs*, so a check and a gate made in two
                // separate sections could let `releaseAll()` land between
                // them and hand back a gate nobody will ever signal again.
                let gate: DispatchSemaphore? = lock.withLock {
                    guard !open else { return nil }
                    let made = gates[query] ?? DispatchSemaphore(value: 0)
                    gates[query] = made
                    parked += 1
                    return made
                }
                guard let gate else { return try JSONEncoder().encode([SearchHit]()) }
                // Off the cooperative pool the way the real wait is: a
                // semaphore parked inside an `async` function would hold one
                // of its threads.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async { gate.wait(); continuation.resume() }
                }
                lock.withLock { parked -= 1 }
                return try JSONEncoder().encode([SearchHit]())
            default:
                return Data()
            }
        }
    }

    /// A real deadline, never an exact sleep and never a bare `Task.yield`
    /// (CLAUDE.md: a yield buys a turn on the pool and no wall-clock time).
    private func waitUntil(_ deadline: Duration = .milliseconds(800),
                           _ condition: @escaping () -> Bool) async {
        let start = ContinuousClock.now
        while !condition(), ContinuousClock.now - start < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// Kept on `self` and set fresh at the top of the one test that builds
    /// one — a test that never builds a transport leaves this `nil`, so
    /// `tearDown` below has nothing to release and does not fail on a case
    /// that never held anything back.
    private var transport: HeldTransport?

    override func tearDown() async throws {
        transport?.releaseAll()
        if let transport {
            await waitUntil(.milliseconds(500)) { transport.parkedCount == 0 }
            XCTAssertEqual(transport.parkedCount, 0, """
                "zzbb"'s own chain is still parked on a `DispatchQueue.global()` thread after \
                teardown — this fixture left a thread parked for the rest of the test process, \
                which is exactly the leak `releaseAll()` exists to close
                """)
        }
        transport = nil
        try await super.tearDown()
    }

    func testADroppedQueuedWordCanBeAskedAgain() async {
        let transport = HeldTransport()
        self.transport = transport
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        vm.searchPause = .milliseconds(30)
        await vm.loadIfNeeded()

        // "zzaa" is sent and held out over the wire.
        vm.query = "zzaa"
        await waitUntil { transport.asked.contains("zzaa") }
        XCTAssertEqual(transport.asked, ["zzaa"], "precondition: \"zzaa\" is out")

        // "zzbb" is typed next: the pause elapses while "zzaa" is still out,
        // so `ask("zzbb")` takes the queue branch — the section claims
        // "zzbb" before a chain for it exists.
        vm.query = "zzbb"
        await waitUntil { vm.searchedQuery == "zzbb" }
        XCTAssertEqual(vm.searchedQuery, "zzbb", "precondition: \"zzbb\" was queued")
        XCTAssertEqual(vm.section, .searching, "precondition: the section claims \"zzbb\"")
        XCTAssertEqual(transport.asked, ["zzaa"], "precondition: \"zzbb\" was never actually sent")

        // The field moves to a word the installed list already answers —
        // "zzbb" is dropped from the queue without ever being asked — and
        // "zzaa"'s own chain is released so its dequeue step runs.
        vm.query = "wget"
        transport.release("zzaa")
        await waitUntil { vm.searchedQuery != "zzbb" }
        XCTAssertNil(vm.searchedQuery, """
            \(String(describing: vm.searchedQuery)) — dropping "zzbb" from the queue must \
            undo the claim queuing made for it, or the word can never be searched again \
            without erasing the field first
            """)

        // Coming back to "zzbb" must reach brew again rather than sit behind
        // a "Searching…" nobody will ever answer.
        vm.query = "zzbb"
        await waitUntil { transport.asked.contains("zzbb") }
        XCTAssertTrue(transport.asked.contains("zzbb"), """
            \(transport.asked) — "zzbb" was dropped from the queue and never asked again; \
            the section was stuck at .searching with no way back except erasing the field
            """)
    }
}
