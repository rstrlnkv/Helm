import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// Kept: guards the stored `module.homebrew.updateBeforeChecking`. A Mac that never wrote it must
/// still run `brew outdated` with brew's own refresh, the bytes it ran with before the setting existed.
final class AnAbsentUpdateSettingUpdatesAsBeforeTests: XCTestCase {
    private let key = "module.homebrew.updateBeforeChecking"

    /// The `outdated` call's environment, asserted only after it is known to have run.
    private func outdatedEnvironment(stored: Any?, file: StaticString = #filePath, line: UInt = #line)
        -> (env: [String: String]?, backing: InMemoryKeyValueStore) {
        let backing = InMemoryKeyValueStore()
        if let stored { backing.raw = [key: stored] }
        let runner = ScriptedRunner()
        let engine = HomebrewEngine(
            locator: FixedLocator(), runner: runner, privileged: NoPrivileges(), user: "tester",
            marker: InMemoryOpMarker(),
            updateBeforeChecking: UpdateBeforeChecking(
                store: NamespacedStore(namespace: HomebrewEngine.moduleID, backing: backing)))
        _ = engine.outdated()
        let call = runner.calls.first { $0.args.first == "outdated" }
        XCTAssertNotNil(call, "outdated never ran", file: file, line: line)
        return (call?.env, backing)
    }

    func testAStoreWithNoKeyRefreshesAsBefore() {
        let (env, backing) = outdatedEnvironment(stored: nil)
        XCTAssertNil(env?["HOMEBREW_NO_AUTO_UPDATE"])
        XCTAssertNil(backing.object(forKey: key), "reading wrote the default back")
    }

    func testStoredFalseRefusesTheRefresh() {
        XCTAssertEqual(outdatedEnvironment(stored: false).env?["HOMEBREW_NO_AUTO_UPDATE"], "1")
    }

    func testStoredTrueRefreshes() {
        XCTAssertNil(outdatedEnvironment(stored: true).env?["HOMEBREW_NO_AUTO_UPDATE"])
    }

    func testStoredGarbageReadsOnAndWritesNothingBack() {
        let (env, backing) = outdatedEnvironment(stored: "no")
        XCTAssertNil(env?["HOMEBREW_NO_AUTO_UPDATE"])
        XCTAssertEqual(backing.object(forKey: key) as? String, "no")
    }
}
