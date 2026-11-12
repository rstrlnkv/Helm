import XCTest
import HelmTestSupport

/// `preferences:` defaults to `SystemCapturePreferences()`, which reads the owner's
/// own screencapture defaults and shortcuts, so a construction that forgets it
/// makes the answer a fact about whoever runs the suite.
///
/// The scan itself is `PortsAtConstruction`, shared, and this file is the wiring.
final class EveryEngineNamesItsPortsTests: XCTestCase {

    func testEveryConstructionInThisModulesTestsNamesEveryPort() throws {
        try PortsAtConstruction.check("ScreenshotsEngine",
                                      under: "Tests/Modules/Screenshots",
                                      naming: ["preferences"],
                                      atLeast: 2)
    }
}
