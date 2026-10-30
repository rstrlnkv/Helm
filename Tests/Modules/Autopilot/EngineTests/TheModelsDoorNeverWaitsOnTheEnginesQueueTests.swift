import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The cheap members of the model's door are never put on the engine's serial queue.
///
/// `status` reads `historyRefused` and `clearHistory` clears: both take `queue.sync`.
/// A member of the door that ran them *on* that queue (`offQueue`) would sync onto
/// the queue it is standing on, which libdispatch traps: the app would die at the
/// first opening of the page. So the six cheap members run
/// off the cooperative pool, and only the walk and the move members run on the queue.
///
/// The queue is parked by a dry run's walk: the reader's `weigh` seam is called on
/// the queue for each file. Total failure of the subject (the queue never parked)
/// shows as the precondition naming the walk that never began; a member put on the
/// queue shows as the test process dying (signal 5) or, if it lands only behind
/// the parked walk, as a 5 s expectation timing out.
final class TheModelsDoorNeverWaitsOnTheEnginesQueueTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var engine: AutopilotEngine!
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let parked = ParkedFlag()

    private final class ParkedFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        func claim() -> Bool { lock.withLock { defer { done = true }; return !done } }
    }

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Files")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        engine = AutopilotEngine(store: NamespacedStore(namespace: "rules.test.\(UUID().uuidString)",
                                                        backing: InMemoryKeyValueStore()),
                                 home: home.path, keys: TestRuleKey(), sequence: TestRuleSequence())
        let (entered, release, parked) = (self.entered, self.release, self.parked)
        engine.reader.weigh = { _ in
            if parked.claim() { entered.signal(); release.wait() }
            return 1
        }
        // Whatever happens below, the queue is let go: a red run must not leave a
        // thread parked for the rest of the suite.
        addTeardownBlock { for _ in 0..<4 { release.signal() } }
    }

    private var folder: WatchedFolder {
        WatchedFolder(id: "f", path: root.path, enabled: true,
                      rules: [Rule(id: "r", name: "Sort", enabled: true,
                                   conditions: [.fileExtension(["pdf"])],
                                   action: .sortIntoSubfolder(.kind))],
                      depth: 1)
    }

    private func finishing(_ what: String, _ work: @escaping @Sendable () async -> Void) -> XCTestExpectation {
        let done = expectation(description: what)
        Task { await work(); done.fulfill() }
        return done
    }

    func testTheStatusAndTheHistoryAreAnsweredWhileASweepHoldsTheQueue() async throws {
        try write("a.pdf", in: root)
        let engine = self.engine!
        let draft = folder
        await engine.save([draft])

        let walk = finishing("the dry run, after the release") { _ = await engine.dryRun(draft) }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success,
                       "precondition: the dry run's walk never reached the reader, so the queue was not parked")

        // Not behind the queue at all: these two answer while it is held.
        let reads = [
            finishing("readFolders") { _ = await engine.readFolders() },
            finishing("readHistory") { _ = await engine.readHistory() },
        ]
        await fulfillment(of: reads, timeout: 5)

        // Behind the queue by their own `queue.sync`, and answered once it is let
        // go: on the queue they would never be.
        let waiting = [
            finishing("readStatus") { _ = await engine.readStatus() },
            finishing("dropHistory") { await engine.dropHistory() },
        ]
        release.signal()
        await fulfillment(of: waiting + [walk], timeout: 5)
    }
}
