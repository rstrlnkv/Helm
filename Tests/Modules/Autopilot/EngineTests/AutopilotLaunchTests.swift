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
final class AutopilotLaunchTests: XCTestCase {

    private var home: URL!
    private var root: URL!
    private var backing: InMemoryKeyValueStore!
    private var namespace: String!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
    }

    private func store() -> NamespacedStore {
        NamespacedStore(namespace: namespace, backing: backing)
    }

    private func engine(_ keys: RuleKeyPort) -> AutopilotEngine {
        AutopilotEngine(store: store(), home: home.path, keys: keys, sequence: TestRuleSequence())
    }

    /// A barrier on the engine's own queue: `clearHistory` is `queue.sync`, and
    /// the queue is serial, so anything `activate` enqueued has finished by the
    /// time this returns. A barrier rather than a sleep — a sleep would be the
    /// race-satisfiable assertion this whole file exists to avoid.
    private func barrier(_ engine: AutopilotEngine) { engine.clearHistory() }

    // MARK: - Construction

    /// Building the engine does not ask for the key: `activate` reads the rule
    /// set, and with it the key, a moment later, so a read in `init` would buy
    /// nothing and cost the whole launch.
    func testConstructingTheEngineDoesNotConsultTheKeyPort() {
        let keys = TestRuleKey()

        _ = engine(keys)

        XCTAssertEqual(keys.reads, 0,
                       "the keychain was read while the engine was being built")
    }

    // MARK: - What the eager read was protecting

    /// The keychain item's absence is the only evidence that this installation
    /// predates sealing, so it has to start existing at the first launch;
    /// otherwise a machine with no rules stays in migration and a rule set
    /// planted a month later is adopted as one that predates the seal.
    ///
    /// `activate` makes that true. Asserted the only way that means anything:
    /// plant an emptying rule set afterwards and check the file is still there.
    func testTheFirstLaunchLeavesMigrationEvenWithNoRulesToRead() throws {
        try Data("private".utf8).write(to: root.appendingPathComponent("statement.pdf"))
        let helm = engine(TestRuleKey())

        helm.activate()
        barrier(helm)
        helm.deactivate()

        backing.raw["module.\(namespace!).folders"] = try JSONEncoder().encode(
            emptyingRules(in: root))
        helm.sweepAll()

        XCTAssertEqual(tree(under: root), ["statement.pdf"],
                       "rules planted after the first launch were adopted and run")
        XCTAssertNotNil(helm.status.refusal)
    }
}
