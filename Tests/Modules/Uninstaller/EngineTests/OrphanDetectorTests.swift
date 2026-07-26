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

    // MARK: - Apps the directory listing cannot see

    /// /Applications is not a flat list. Acrobat lives in "Adobe Acrobat DC/",
    /// and OneDrive carries a SharePoint helper *inside* its own bundle —
    /// both were reported as leftovers of uninstalled software while running.
    func testAnAppTheSystemKnowsIsNotAnOrphan() {
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.adobe.Acrobat.Pro",
                                               installedBundleIDs: [],
                                               knownToSystem: { $0 == "com.adobe.Acrobat.Pro" }))
    }

    func testAnAppNobodyKnowsIsStillAnOrphan() {
        XCTAssertTrue(OrphanDetector.isOrphan(name: "com.acme.gone",
                                              installedBundleIDs: [],
                                              knownToSystem: { _ in false }))
    }

    /// The directory list still counts, so the lookup is a second chance and
    /// never a veto in the other direction.
    func testDirectoryListStillWins() {
        XCTAssertFalse(OrphanDetector.isOrphan(name: "com.acme.tool",
                                               installedBundleIDs: ["com.acme.tool"],
                                               knownToSystem: { _ in false }))
    }
}
