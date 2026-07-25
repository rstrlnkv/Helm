import XCTest
@testable import Module_Leftovers_Engine

/// The module deletes files macOS still loads at login. Getting the safety
/// rules wrong breaks someone's machine, so they are the first thing tested.
final class StaleItemRulesTests: XCTestCase {
    private let installed: Set<String> = ["com.acme.tool", "com.other.app"]

    // MARK: - What is never offered

    func testAppleItemsAreNeverOffered() {
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "com.apple.dock", path: "/Users/x/Library/Preferences/com.apple.dock.plist",
            ownerInstalled: false, installedIDs: installed))
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "com.apple.something", path: "/Library/LaunchAgents/com.apple.something.plist",
            ownerInstalled: false, installedIDs: installed))
    }

    func testSystemLocationsAreNeverOffered() {
        for path in ["/System/Library/LaunchAgents/x.plist",
                     "/Library/Apple/System/Library/LaunchDaemons/y.plist",
                     "/usr/lib/z.plist"] {
            XCTAssertFalse(StaleItemRules.isRemovable(
                identifier: "com.vendor.thing", path: path,
                ownerInstalled: false, installedIDs: installed), path)
        }
    }

    /// An item whose owner is still installed is in use, not a leftover.
    func testItemsOfInstalledAppsAreNotOffered() {
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "com.acme.tool", path: "/Users/x/Library/Preferences/com.acme.tool.plist",
            ownerInstalled: true, installedIDs: installed))
        // Even a helper id under an installed app's prefix stays.
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "com.acme.tool.helper", path: "/Users/x/Library/Preferences/com.acme.tool.helper.plist",
            ownerInstalled: false, installedIDs: installed))
    }

    /// Globals like ".GlobalPreferences" belong to macOS itself.
    func testDotPrefixedAndUnidentifiedFilesAreNotOffered() {
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: ".GlobalPreferences", path: "/Users/x/Library/Preferences/.GlobalPreferences.plist",
            ownerInstalled: false, installedIDs: installed))
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "", path: "/Users/x/Library/Preferences/random.plist",
            ownerInstalled: false, installedIDs: installed))
    }

    // MARK: - What is offered

    func testOrphanedThirdPartyItemsAreOffered() {
        XCTAssertTrue(StaleItemRules.isRemovable(
            identifier: "com.gone.vendor.app",
            path: "/Users/x/Library/Preferences/com.gone.vendor.app.plist",
            ownerInstalled: false, installedIDs: installed))
        XCTAssertTrue(StaleItemRules.isRemovable(
            identifier: "com.gone.vendor.agent",
            path: "/Users/x/Library/LaunchAgents/com.gone.vendor.agent.plist",
            ownerInstalled: false, installedIDs: installed))
    }

    /// A reverse-DNS id needs at least vendor + name to be judged.
    func testIdentifiersMustLookLikeBundleIDs() {
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "settings", path: "/Users/x/Library/Preferences/settings.plist",
            ownerInstalled: false, installedIDs: installed))
    }

    // MARK: - Vendor safety (learned from a dry run on a real machine)

    /// Adobe and Microsoft ship settings under ids that match no app bundle:
    /// com.adobe.Photoshop, com.microsoft.office. Judging each id on its own
    /// offered to delete the settings of installed software.
    func testItemsAreKeptWhenTheVendorHasAnyInstalledApp() {
        let installed: Set<String> = ["com.adobe.Photoshop.2026", "com.microsoft.Word"]
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "com.adobe.Photoshop", path: "/Users/x/Library/Preferences/com.adobe.Photoshop.plist",
            ownerInstalled: false, installedIDs: installed))
        XCTAssertFalse(StaleItemRules.isRemovable(
            identifier: "com.microsoft.office", path: "/Users/x/Library/Preferences/com.microsoft.office.plist",
            ownerInstalled: false, installedIDs: installed))
        // A vendor with nothing installed is still fair game.
        XCTAssertTrue(StaleItemRules.isRemovable(
            identifier: "com.gone.vendor.app", path: "/Users/x/Library/Preferences/com.gone.vendor.app.plist",
            ownerInstalled: false, installedIDs: installed))
    }

    /// Shared plumbing that belongs to no single app.
    func testSharedAndSystemNamespacesAreNeverOffered() {
        for id in ["systemgroup.com.apple.icloud.searchpartyd.sharedsettings",
                   "group.com.firecore.infuse.firebase",
                   "org.cups.PrintingPrefs",
                   "org.sparkle-project.Sparkle.Autoupdate"] {
            XCTAssertFalse(StaleItemRules.isRemovable(
                identifier: id, path: "/Users/x/Library/Preferences/\(id).plist",
                ownerInstalled: false, installedIDs: []), id)
        }
    }
}
