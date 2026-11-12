import XCTest
import HelmTestSupport

/// `home:` defaults to `NSHomeDirectory()`, the reference `WatchScope` judges every
/// sweep against, so a construction that forgets it asks the gate about the
/// owner's folders while claiming to be about a scratch directory. The keychain
/// ports are held by `ATestNamesTheKeychainPortsItBuildsOverTests`.
///
/// The scan itself is `PortsAtConstruction`, shared, and this file is the wiring.
final class EveryEngineNamesItsHomeTests: XCTestCase {

    func testEveryConstructionInThisModulesTestsNamesEveryPort() throws {
        try PortsAtConstruction.check("AutopilotEngine",
                                      under: "Tests/Modules/Autopilot",
                                      naming: ["home"],
                                      atLeast: 37)
    }
}
