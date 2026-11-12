import XCTest
@testable import HelmRuntime

/// What a reset is allowed to remove. The gate exists because this is the one
/// feature in the app whose whole purpose is deletion, and the list it produces
/// is handed straight to the Trash.
final class ResetPlanTests: XCTestCase {
    private let home = "/Users/someone"

    func testItNamesTheTwoHelmDirectories() {
        let paths = ResetPlan.removablePaths(home: home, folder: .helm)
        XCTAssertEqual(Set(paths), [
            "\(home)/Library/Application Support/Helm",
            "\(home)/Library/Logs/Helm",
        ])
    }

    /// The release, a test runner and nil are `.helm`; Helm Dev is `.helmDev`.
    func testEveryPathItProducesIsInsideTheHomeAndNamesTheBuildsFolder() {
        for id in ["com.helm.app", AppBuild.devIdentifier, nil] as [String?] {
            let folder = DataFolder.of(identifier: id)
            let name = AppBuild.isDevIdentifier(id) ? "Helm Dev" : "Helm"
            XCTAssertEqual(Set(ResetPlan.removablePaths(home: home, folder: folder)), [
                "\(home)/Library/Application Support/\(name)",
                "\(home)/Library/Logs/\(name)",
            ], "\(id ?? "nil")")
        }
    }

    /// What Dev's reset hands to the Trash, from the call the app makes: Helm Dev's
    /// folders only, never the real Helm's.
    func testHelmDevsResetNamesOnlyHelmDevsFolders() {
        XCTAssertEqual(Set(ResetPlan.trashPaths(home: home, identifier: AppBuild.devIdentifier)), [
            "\(home)/Library/Application Support/Helm Dev",
            "\(home)/Library/Logs/Helm Dev",
        ])
        XCTAssertEqual(Set(ResetPlan.trashPaths(home: home, identifier: "com.helm.app")), [
            "\(home)/Library/Application Support/Helm",
            "\(home)/Library/Logs/Helm",
        ])
    }

    /// The gate, asked the questions somebody would ask it by accident.
    func testItRefusesAnythingThatIsNotHelmsOwn() {
        for path in ["\(home)/Library", "\(home)/Documents", "\(home)",
                     "/", "/System/Library", "\(home)/Library/Application Support",
                     "\(home)/Library/Logs", "\(home)/Library/Application Support/Helmet",
                     "\(home)/Library/Application Support/Helm/../../Documents"] {
            XCTAssertFalse(ResetPlan.mayRemove(path, home: home, folder: .helm),
                           "\(path) must not be removable by a reset")
        }
    }

    func testItAllowsHelmsOwnDirectoriesAndWhatIsInThem() {
        for path in ["\(home)/Library/Application Support/Helm",
                     "\(home)/Library/Application Support/Helm/Disk",
                     "\(home)/Library/Logs/Helm",
                     "\(home)/Library/Logs/Helm/helm.log"] {
            XCTAssertTrue(ResetPlan.mayRemove(path, home: home, folder: .helm), "\(path) is Helm's own")
        }
    }
}
