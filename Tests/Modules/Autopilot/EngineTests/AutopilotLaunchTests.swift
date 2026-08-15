import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// What the engine may do while it is being built and started.
///
/// `ModuleHost.bootstrap()` builds and activates every enabled module's engine
/// on the main thread inside `applicationDidFinishLaunching`, before the status
/// item exists. So anything either of those does synchronously is something the
/// user waits for with no menu bar and no window — the app looks like it did
/// not start.
///
/// The blocking is a timing property and a stopwatch assertion would pass on a
/// fast machine by luck. These assert the structure instead: how many times the
/// port was consulted, and whether construction completes while it has not
/// answered at all. A port that never answers cannot be beaten by a race.
final class AutopilotLaunchTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var backing: InMemoryKeyValueStore!
    private var namespace: String!
    private var stalled: StalledRuleKey!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
        stalled = StalledRuleKey()
    }

    override func tearDownWithError() throws {
        stalled.release()
        try? FileManager.default.removeItem(at: home)
    }

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: namespace, backing: backing)
    }

    private func engine(_ keys: RuleKeyPort) -> AutopilotEngine {
        AutopilotEngine(store: store(), home: home.path, keys: keys, sequence: TestRuleSequence())
    }

    /// Builds the engine on another thread and gives up after five seconds.
    ///
    /// Not caution: a construction that consults `StalledRuleKey` never returns,
    /// and building it on the test's own thread parks the whole suite instead of
    /// failing it. A regression has to be reported, not waited for.
    private func engineOffThread(_ keys: RuleKeyPort) throws -> AutopilotEngine {
        let built = expectation(description: "the engine was built")
        let store = store()
        let home = self.home!
        let box = Box()
        DispatchQueue.global().async {
            box.engine = AutopilotEngine(store: store, home: home.path, keys: keys, sequence: TestRuleSequence())
            built.fulfill()
        }
        wait(for: [built], timeout: 5)
        return try XCTUnwrap(box.engine, "the engine was never built")
    }

    private final class Box: @unchecked Sendable { var engine: AutopilotEngine? }

    /// A barrier on the engine's own queue: `clearHistory` is `queue.sync`, and
    /// the queue is serial, so anything `activate` enqueued has finished by the
    /// time this returns. A barrier rather than a sleep — a sleep would be the
    /// race-satisfiable assertion this whole file exists to avoid.
    private func settle(_ engine: AutopilotEngine) { engine.clearHistory() }

    // MARK: - Construction

    /// The defect, at its site. `AutopilotEngine.init` read the key so that the
    /// keychain item would exist from the first launch of the sealing build;
    /// `activate` reads the rule set — and therefore the key — a moment later
    /// anyway, so the eager read bought nothing and cost the whole launch.
    func testConstructingTheEngineDoesNotConsultTheKeyPort() {
        let keys = TestRuleKey()

        _ = engine(keys)

        XCTAssertEqual(keys.reads, 0,
                       "the keychain was read while the engine was being built")
    }

    /// And the same statement made against a port that cannot be raced: if
    /// construction consults it, this never fulfils, whatever the machine.
    func testAnEngineIsBuiltWhileTheKeyPortNeverAnswers() throws {
        _ = try engineOffThread(stalled)
    }

    // MARK: - Starting

    /// `activate` is the other half of `bootstrap`, on the same main thread. It
    /// reads the rule set to know which folders to watch, and that read reaches
    /// the keychain — so it has to hand the work to the engine's queue and
    /// return.
    func testActivateReturnsWhileTheKeyPortNeverAnswers() throws {
        let helm = try engineOffThread(stalled)
        let returned = expectation(description: "activate returned")

        DispatchQueue.global().async {
            helm.activate()
            returned.fulfill()
        }

        wait(for: [returned], timeout: 5)
        helm.deactivate()
    }

    /// The lock the prompt must not be held under. `trustLock` also answers
    /// `rulesRefused`, which the settings page reads on the main actor: holding
    /// it across the port call put the modal prompt between the UI and its own
    /// state.
    func testRefusalCanBeReadWhileTheKeyPortHasNotAnswered() throws {
        let helm = try engineOffThread(stalled)
        DispatchQueue.global().async { _ = helm.folders }
        XCTAssertTrue(stalled.waitUntilAsked(), "the premise: something is inside key()")

        let answered = expectation(description: "rulesRefused answered")
        DispatchQueue.global().async {
            _ = helm.rulesRefused
            answered.fulfill()
        }

        wait(for: [answered], timeout: 5)
    }

    // MARK: - What the eager read was protecting

    /// The reason `init` read the key, kept. The keychain item's absence is the
    /// only evidence that this installation predates sealing, so it has to start
    /// existing at the first launch — otherwise a machine with no rules stays in
    /// migration and a rule set planted a month later is adopted as one that
    /// predates the seal.
    ///
    /// `activate` is what makes that true now. Asserted the only way that means
    /// anything: plant an emptying rule set afterwards and check the file is
    /// still there.
    func testTheFirstLaunchLeavesMigrationEvenWithNoRulesToRead() throws {
        try Data("private".utf8).write(to: root.appendingPathComponent("statement.pdf"))
        let helm = engine(TestRuleKey())

        helm.activate()
        settle(helm)
        helm.deactivate()

        backing.raw["module.\(namespace!).folders"] = try JSONEncoder().encode(
            [WatchedFolder(id: "planted", path: root.path, enabled: true, rules: [
                Rule(id: "r", name: "take it", enabled: true, match: .all,
                     conditions: [.fileExtension(["pdf"])], action: .trash),
            ], depth: 1)])
        helm.sweepAll()

        XCTAssertEqual((FileManager.default.enumerator(atPath: root.path)?
            .allObjects as? [String])?.sorted(), ["statement.pdf"],
                       "rules planted after the first launch were adopted and run")
        XCTAssertTrue(helm.rulesRefused)
    }
}
