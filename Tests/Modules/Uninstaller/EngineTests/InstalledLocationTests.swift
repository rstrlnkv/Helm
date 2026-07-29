import XCTest
@testable import Module_Uninstaller_Engine

/// Which bundles count as *installed* when two of them declare one id.
///
/// LaunchServices answers "where are the apps with this id" with every copy it
/// has ever registered, and most of those are not installations: the disk image
/// the app was dragged out of, the download beside it, and — the one that would
/// break every scan — the copy an updater stages under `~/Library/Caches`,
/// which carries the very same bundle id as the app it is about to replace.
/// Counting a staged copy as a rival would leave every Sparkle-updated app
/// looking contested, so the test that matters here is that it does not.
///
/// Positional, like `RemovableScope`: a place an application is installed in,
/// not a list of places to distrust.
final class InstalledLocationTests: XCTestCase {
    private let home = "/Users/x"

    private func installed(_ path: String) -> Bool {
        InstalledLocation.isInstalled(path: path, home: home)
    }

    func testTheApplicationsFolderIsWhereAppsAreInstalled() {
        XCTAssertTrue(installed("/Applications/Tool.app"))
        XCTAssertTrue(installed("/Users/x/Applications/Tool.app"))
    }

    /// The whole point of asking the system: the app one folder down, which the
    /// directory listing never sees.
    func testAnAppOneFolderDownIsStillInstalled() {
        XCTAssertTrue(installed("/Applications/Adobe Acrobat DC/Adobe Acrobat.app"))
        XCTAssertTrue(installed("/Applications/Setapp/Tool.app"))
    }

    func testMacOSsOwnApplicationsCount() {
        XCTAssertTrue(installed("/System/Applications/Music.app"))
        XCTAssertTrue(installed("/System/Library/CoreServices/Finder.app"))
    }

    /// A staged update carries the id of the app it replaces. It is the app
    /// being removed, not a rival, and treating it as one would silence the
    /// scan for every app that updates itself.
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
