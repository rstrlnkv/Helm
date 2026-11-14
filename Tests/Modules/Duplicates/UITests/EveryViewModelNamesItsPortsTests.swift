import XCTest
import HelmTestSupport

/// `chooseFolder:` defaults to the system's open panel, which blocks on a person,
/// so a construction that forgets it turns a press into a modal panel on whoever
/// runs the suite. `settings:` is held by `ATestNamesTheKeychainPortsItBuildsOverTests`.
///
/// The scan itself is `PortsAtConstruction`, shared, and this file is the wiring.
final class EveryViewModelNamesItsPortsTests: XCTestCase {

    func testEveryConstructionInThisModulesTestsNamesTheFolderPanel() throws {
        try PortsAtConstruction.check("DuplicatesViewModel",
                                      under: "Tests/Modules/Duplicates",
                                      naming: ["chooseFolder"],
                                      atLeast: 7)
    }
}
