import XCTest
@testable import Module_Uninstaller_Engine

/// Which bundles count as *installed* when two of them declare one id.
///
/// LaunchServices answers with every copy it has registered, and most are not
/// installations: the disk image, the download, and the copy an updater stages
/// under `~/Library/Caches`, which as a rival would make every self-updating
/// app look contested.
final class InstalledLocationTests: XCTestCase {
    private let home = "/Users/x"

    private func installed(_ path: String) -> Bool {
        InstalledLocation.isInstalled(path: path, home: home)
    }

    func testTheApplicationsFolderIsWhereAppsAreInstalled() {
        XCTAssertTrue(installed("/Applications/Tool.app"))
        XCTAssertTrue(installed("/Users/x/Applications/Tool.app"))
    }

    /// The app one folder down, which the directory listing never sees.
    func testAnAppOneFolderDownIsStillInstalled() {
        XCTAssertTrue(installed("/Applications/Adobe Acrobat DC/Adobe Acrobat.app"))
        XCTAssertTrue(installed("/Applications/Setapp/Tool.app"))
    }

    func testMacOSsOwnApplicationsCount() {
        XCTAssertTrue(installed("/System/Applications/Music.app"))
        XCTAssertTrue(installed("/System/Library/CoreServices/Finder.app"))
    }

    /// A staged update carries the id of the app it replaces, and is not a rival.
    func testACopyStagedByAnUpdaterIsNotAnInstallation() {
        XCTAssertFalse(installed("/Users/x/Library/Caches/com.acme.tool/update/Tool.app"))
        XCTAssertFalse(installed("/Users/x/Library/Application Support/Acme/Tool.app"))
    }

    /// The disk image it was dragged out of, and the download beside it.
    func testACopyIsNotAnInstallation() {
        XCTAssertFalse(installed("/Volumes/Tool 3.1/Tool.app"))
        XCTAssertFalse(installed("/Users/x/Downloads/Tool.app"))
        XCTAssertFalse(installed("/Users/x/Desktop/Tool.app"))
        XCTAssertFalse(installed("/Users/x/.Trash/Tool.app"))
    }

    /// A prefix test is not a path test: another account's folder starts with
    /// the same characters as this one's.
    func testANeighbouringNameIsNotInsideTheFolder() {
        XCTAssertFalse(installed("/Applications Old/Tool.app"))
        XCTAssertFalse(installed("/Users/xavier/Applications/Tool.app"))
    }

    /// The folder itself is not an app in it.
    func testTheFolderItselfIsNotAnInstalledApp() {
        XCTAssertFalse(installed("/Applications"))
    }
}
