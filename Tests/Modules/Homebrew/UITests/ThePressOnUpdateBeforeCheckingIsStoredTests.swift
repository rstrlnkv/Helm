import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// A press on the Updates tab's toggle reaches the store the engine reads at its next
/// `outdated`, and a model built over a stored value shows it.
@MainActor
final class ThePressOnUpdateBeforeCheckingIsStoredTests: XCTestCase {
    private let key = "module.homebrew.updateBeforeChecking"

    private func model(_ backing: InMemoryKeyValueStore) -> HomebrewViewModel {
        let setting = UpdateBeforeChecking(store: NamespacedStore(namespace: HomebrewEngine.moduleID, backing: backing))
        let engine = HomebrewEngine(locator: FixedLocator(), runner: FakeBrew(), privileged: NoPrivileges(),
                                    user: "tester", marker: InMemoryOpMarker(), updateBeforeChecking: setting)
        return HomebrewViewModel(work: engine, updateBeforeChecking: setting)
    }

    func testAPressWritesTheStoreKey() {
        let backing = InMemoryKeyValueStore()
        let m = model(backing)
        m.setRefreshesBeforeChecking(false)
        XCTAssertEqual(backing.object(forKey: key) as? Bool, false)
        XCTAssertFalse(m.refreshesBeforeChecking)
        m.setRefreshesBeforeChecking(true)
        XCTAssertEqual(backing.object(forKey: key) as? Bool, true)
        XCTAssertTrue(m.refreshesBeforeChecking)
    }

    func testAModelShowsWhatIsStored() {
        let backing = InMemoryKeyValueStore()
        backing.raw = [key: false]
        XCTAssertFalse(model(backing).refreshesBeforeChecking)
        XCTAssertTrue(model(InMemoryKeyValueStore()).refreshesBeforeChecking)
    }

    /// The descriptor hands the module's own namespace to the model it builds: a press on the
    /// toggle of a module made the way the host makes it reaches the stored key.
    func testTheModuleTheHostMakesWritesThePressToItsStore() {
        let backing = InMemoryKeyValueStore()
        let parts = HomebrewDescriptor().makeModule(store: NamespacedStore(namespace: HomebrewEngine.moduleID, backing: backing))
        defer { parts.model.stop() }
        parts.model.setRefreshesBeforeChecking(false)
        XCTAssertEqual(backing.object(forKey: key) as? Bool, false)
    }

    /// The engine the host makes reads the same setting the toggle writes: after a press OFF,
    /// the next `outdated` runs with brew's own refresh switched off.
    func testThePressReachesTheEngineTheHostMakes() throws {
        let runner = FakeBrew()
        let parts = HomebrewDescriptor().makeModule(
            store: NamespacedStore(namespace: HomebrewEngine.moduleID, backing: InMemoryKeyValueStore()),
            locator: FixedLocator(), runner: runner)
        defer { parts.model.stop() }
        let engine = try XCTUnwrap(parts.engine as? HomebrewEngine)
        parts.model.setRefreshesBeforeChecking(false)
        _ = engine.outdated()
        let call = runner.calls.first { $0.args.first == "outdated" }
        XCTAssertNotNil(call, "outdated never ran")
        XCTAssertEqual(call?.env["HOMEBREW_NO_AUTO_UPDATE"], "1")
    }
}
