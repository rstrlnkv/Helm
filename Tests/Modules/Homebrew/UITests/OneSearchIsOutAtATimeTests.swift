import XCTest
import HelmContract
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **At most one `brew search` chain out at a time.**
///
/// `HomebrewViewModel.ask(_:)` is CLAUDE.md's "never an unbounded launch
/// behind a control a person can press repeatedly" answered for a field that
/// asks brew on every keystroke that qualifies: a press while a chain is out
/// queues only the newest word, and an older one typed in between is dropped
/// along with its own `brew search`. Nothing in the tree exercised the queue
/// itself before this file — every other test's fake answers at once, so two
/// chains could never overlap and the gate was unreachable.
///
/// Modelled on `AStaleSearchDoesNotLandOnANewerOneTests`'s held-gate
/// transport: a fake that answered immediately would make the ordering this
/// file is about impossible to reach (CLAUDE.md § What not to do, and what
/// breaks if you do).
@MainActor
final class OneSearchIsOutAtATimeTests: XCTestCase {

    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        private let stream = AsyncStream<EngineEvent>.makeStream()
        var events: AsyncStream<EngineEvent> { stream.stream }

        private let installedList: [BrewPackage]
        init(installed: [BrewPackage] = []) { installedList = installed }

        private let lock = NSLock()
        private var _searches: [String] = []
        var searches: [String] { lock.lock(); defer { lock.unlock() }; return _searches }

        private var gates: [String: DispatchSemaphore] = [:]
        // Synchronous, and that is not a style choice: Swift 6 makes
        // `NSLock.lock()` unavailable inside an `async` function outright
        // (`AStaleSearchDoesNotLandOnANewerOneTests`'s own reason).
        private func gate(for query: String) -> DispatchSemaphore {
            lock.lock(); defer { lock.unlock() }
            if let existing = gates[query] { return existing }
            let made = DispatchSemaphore(value: 0)
            gates[query] = made
            return made
        }
        /// Lets the search for `query` answer, with no hits.
        func release(_ query: String) { gate(for: query).signal() }

        private func entered(_ query: String) {
            lock.lock(); _searches.append(query); lock.unlock()
        }

        func send(_ command: EngineCommand) async throws -> Data {
            switch HomebrewCommand(rawValue: command.name) {
            case .status:
                return try JSONEncoder().encode(
                    BrewStatus(installed: true, brewPath: "/opt/fixture/bin/brew"))
            case .listInstalled: return try JSONEncoder().encode(installedList)
            case .descriptions: return try JSONEncoder().encode([String: String]())
            case .search:
                let query = String(data: command.payload, encoding: .utf8) ?? ""
                entered(query)
                let g = gate(for: query)
                // Off the cooperative pool the way the real wait is: a
                // semaphore parked inside an `async` function would hold one
                // of its threads.
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    DispatchQueue.global().async { g.wait(); continuation.resume() }
                }
                return try JSONEncoder().encode([SearchHit]())
            default: return Data()
            }
        }
    }

    /// A real deadline, never a bare `Task.yield` (ARCHITECTURE.md § Tests and
    /// measurement: a yield buys a turn on the pool and no wall-clock time).
    private func waitUntil(_ deadline: Duration = .seconds(2),
                          _ condition: () -> Bool) async {
        let start = ContinuousClock.now
        while !condition(), ContinuousClock.now - start < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func testAWordTypedWhileAChainIsOutIsQueuedNotLaunched() async {
        let transport = HeldTransport()
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await vm.loadIfNeeded()

        vm.query = "AAAA"
        vm.searchNow()
        await waitUntil { transport.searches == ["AAAA"] }
        XCTAssertEqual(transport.searches, ["AAAA"], "precondition: the first ask is out")

        // B is typed and asked for while A is still held — this must queue
        // rather than launch a second chain.
        vm.query = "BBBB"
        vm.searchNow()
        // C supersedes B before B has ever been sent at all.
        vm.query = "CCCC"
        vm.searchNow()

        try? await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(transport.searches, ["AAAA"], """
            \(transport.searches) — a second chain launched while the first was still out, \
            which is the unbounded-launch-behind-a-repeatable-control defect CLAUDE.md names
            """)
        XCTAssertEqual(vm.section, .searching, """
            "Searching…" must name the word that will actually be asked next (C), not the \
            one still in flight (A)
            """)

        transport.release("AAAA")
        await waitUntil { transport.searches.count == 2 }
        XCTAssertEqual(transport.searches, ["AAAA", "CCCC"], """
            \(transport.searches) — B must never reach the transport at all, only the newest \
            word queued behind A
            """)

        transport.release("CCCC")
        await waitUntil { vm.searchReading == .answered }
    }

    /// The precondition the test above rests on: a single search, with
    /// nothing queued behind it, still draws its own hits — without this the
    /// case above would hold on a view model that never asks anything.
    func testOneSearchAloneStillDrawsItsHits() async {
        let transport = HeldTransport()
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await vm.loadIfNeeded()

        vm.query = "ZZZZ"
        vm.searchNow()
        await waitUntil { transport.searches == ["ZZZZ"] }
        transport.release("ZZZZ")
        await waitUntil { vm.searchReading == .answered }
        XCTAssertEqual(vm.searchReading, .answered)
        XCTAssertEqual(vm.searchedQuery, "ZZZZ")
    }

    // MARK: - The queue is a payload, re-read at the hop

    /// **Erasing the field while a word sits queued must drop that word too,
    /// not merely the pause and the held answer.** `ask(_:)`'s queued branch
    /// used to leave `queuedSearch` set across an empty-needle `queryMoved()`,
    /// so the chain still out for the *previous* word woke up, found a queued
    /// word, and asked brew for it — a `brew search` for a word no longer in
    /// the field at all.
    func testErasingWhileAWordIsQueuedDropsItRatherThanAskingLater() async {
        let transport = HeldTransport()
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await vm.loadIfNeeded()

        vm.query = "AAAA"
        vm.searchNow()
        await waitUntil { transport.searches == ["AAAA"] }

        vm.query = "BBBB"
        vm.searchNow()
        XCTAssertEqual(vm.section, .searching, "precondition: BBBB is queued and named")

        // Erased while AAAA is still out and BBBB sits queued behind it.
        vm.query = ""
        transport.release("AAAA")

        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(transport.searches, ["AAAA"], """
            \(transport.searches) — the queued word must not survive an emptied field, whatever \
            it was
            """)
        XCTAssertNil(vm.section, "an emptied field draws nothing, queued word or not")
    }

    /// **The same hop, the other way: a word typed over the queued one and
    /// matching something local must drop the stale queue too.** The re-read
    /// at the dequeue hop is `ListFilter.needle(query) == queued`, so typing
    /// `wget` — which the installed list already answers — over a queued
    /// `BBBB` must leave `BBBB` unsent, the same as erasing the field does.
    func testChangingToALocallyMatchingWordWhileQueuedDropsTheStaleWord() async {
        let transport = HeldTransport(installed: [BrewPackage(name: "wget", version: "1.25.0",
                                                              isCask: false)])
        let vm = HomebrewViewModel(vm: ModuleViewModel(transport: transport))
        await vm.loadIfNeeded()

        vm.query = "AAAA"
        vm.searchNow()
        await waitUntil { transport.searches == ["AAAA"] }

        vm.query = "BBBB"
        vm.searchNow()
        XCTAssertEqual(vm.searchedQuery, "BBBB", "precondition: BBBB is queued and named")

        // The field now reads something the installed list already answers —
        // nobody is waiting on BBBB any more.
        vm.query = "wget"
        transport.release("AAAA")

        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(transport.searches, ["AAAA"], """
            \(transport.searches) — BBBB was asked for a word the field no longer holds; the \
            dequeue hop must re-read the field rather than trust the payload it queued
            """)
    }
}
