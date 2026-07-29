import XCTest
@testable import HelmRuntime

/// What a reset is allowed to remove. The gate exists because this is the one
/// feature in the app whose whole purpose is deletion, and the list it produces
/// is handed straight to the Trash.
final class ResetPlanTests: XCTestCase {
    private let home = "/Users/someone"

    func testItNamesTheTwoHelmDirectories() {
        let paths = ResetPlan.removablePaths(home: home)
        XCTAssertEqual(Set(paths), [
            "\(home)/Library/Application Support/Helm",
            "\(home)/Library/Logs/Helm",
        ])
    }

    func testEveryPathItProducesIsInsideTheHome() {
        for path in ResetPlan.removablePaths(home: home) {
            XCTAssertTrue(path.hasPrefix(home + "/"), "\(path) escaped the home directory")
        }
    }

    /// The gate, asked the questions somebody would ask it by accident.
    func testItRefusesAnythingThatIsNotHelmsOwn() {
        for path in ["\(home)/Library", "\(home)/Documents", "\(home)",
                     "/", "/System/Library", "\(home)/Library/Application Support",
                     "\(home)/Library/Logs", "\(home)/Library/Application Support/Helmet",
                     "\(home)/Library/Application Support/Helm/../../Documents"] {
            XCTAssertFalse(ResetPlan.mayRemove(path, home: home),
                           "\(path) must not be removable by a reset")
        }
    }

    func testItAllowsHelmsOwnDirectoriesAndWhatIsInThem() {
        for path in ["\(home)/Library/Application Support/Helm",
                     "\(home)/Library/Application Support/Helm/Disk",
                     "\(home)/Library/Logs/Helm",
                     "\(home)/Library/Logs/Helm/helm.log"] {
            XCTAssertTrue(ResetPlan.mayRemove(path, home: home), "\(path) is Helm's own")
        }
    }

    /// Everything the plan produces must pass its own gate. A list and a gate
    /// that disagree is the shape of the bug this pair exists to prevent.
    func testThePlanAgreesWithItsOwnGate() {
        for path in ResetPlan.removablePaths(home: home) {
            XCTAssertTrue(ResetPlan.mayRemove(path, home: home))
        }
    }
}
