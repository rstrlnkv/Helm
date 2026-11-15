import Foundation
import XCTest
import HelmTestSupport
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// The fixture `AutopilotSealTests` and `ARefusedRuleSetIsNotOverwrittenTests`
/// stand on: a scratch home with a Downloads folder, the plist behind a
/// namespaced store, and the engine over them.
class SealedRulesRig: XCTestCase {

    var home: URL!
    var root: URL!
    var backing: InMemoryKeyValueStore!
    var namespace: String!
    var keys: TestRuleKey!

    override func setUpWithError() throws {
        home = scratchDirectory("home")
        root = home.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        backing = InMemoryKeyValueStore()
        namespace = "autopilot.test.\(UUID().uuidString)"
        keys = TestRuleKey()
    }

    func engine() -> AutopilotEngine {
        AutopilotEngine(store: NamespacedStore(namespace: namespace, backing: backing),
                        home: home.path, keys: keys, sequence: TestRuleSequence())
    }
}
