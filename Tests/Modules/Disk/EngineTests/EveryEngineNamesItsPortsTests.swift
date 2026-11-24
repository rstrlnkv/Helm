import XCTest
import HelmTestSupport

/// `capacity:` defaults to `SystemVolumeCapacity()`, which reads this Mac's own
/// volumes, so a construction that forgets it makes the answer a fact about
/// whoever runs the suite.
///
/// The scan itself is `PortsAtConstruction`, shared, and this file is the wiring.
final class EveryEngineNamesItsPortsTests: XCTestCase {

    func testEveryConstructionInThisModulesTestsNamesEveryPort() throws {
        try PortsAtConstruction.check("DiskEngine",
                                      under: "Tests/Modules/Disk",
                                      naming: ["capacity"],
                                      atLeast: 6)
    }
}
