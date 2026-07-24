import XCTest
@testable import Module_Uninstaller_Engine

final class OrphanDetectorTests: XCTestCase {
    let installed: Set<String> = ["com.acme.tool", "com.corp.editor"]

    func testFlagsBundleIdWithNoInstalledApp() {
        XCTAssertTrue(OrphanDetector.isOrphan(name: "com.gone.app", installedBundleIDs: installed))
    }

    func testKeepsInstalledApps() {
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.acme.tool", installedBundleIDs: installed))
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.acme.tool.plist", installedBundleIDs: installed))
    }

    /// ByHost prefs look like `<bundleID>.<UUID>` — still the installed app's data.
    func testKeepsByHostSuffixOfInstalledApp() {
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.acme.tool.5F2A.plist", installedBundleIDs: installed))
    }

    func testSkipsAppleAndHelmDomains() {
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.apple.finder.plist", installedBundleIDs: installed))
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.helm.app.plist", installedBundleIDs: installed))
    }

    /// Plain folder names are ambiguous (could belong to an installed app or the
    /// system), so they are never flagged.
    func testIgnoresNonBundleIdNames() {
        XCTAssertFalse(OrphanDetector.isOrphan(name: "Google", installedBundleIDs: installed))
        XCTAssertFalse(OrphanDetector.isOrphan(name: "My App Data", installedBundleIDs: installed))
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.two", installedBundleIDs: installed))
    }

    func testBundleIdStripsKnownSuffixes() {
        XCTAssertEqual(OrphanDetector.bundleID(from: "com.gone.app.plist"), "com.gone.app")
        XCTAssertEqual(OrphanDetector.bundleID(from: "com.gone.app.savedState"), "com.gone.app")
        XCTAssertEqual(OrphanDetector.bundleID(from: "com.gone.app"), "com.gone.app")
    }
}
