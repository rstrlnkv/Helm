import XCTest
@testable import Module_Uninstaller_Engine

/// The rule behind the glob filter, on its own.
///
/// `GlobMatch` answers "does this pattern match", which is a question about
/// text. Whether the entry that matched is *this app's* is a different
/// question, and the scan never asked it: `com.acme.tool*` matches
/// `com.acme.toolPro` exactly as well as it matches `com.acme.tool.helper`,
/// and only one of those two is the app being removed.
///
/// Two rules, and both are needed. A bundle id is a dotted path, so an id that
/// appears inside a longer name is only the same id when a `.` (or the end of
/// the name) follows it — that separates `com.acme.tool.helper` from
/// `com.acme.toolPro`. And a name that passes *that* can still be a different
/// app: `com.acme.tool.staging` is `com.acme.tool` plus a dot, and it is a
/// product somebody has installed. So the installed set is consulted too, the
/// way `scanOrphansSync` already consults it.
final class LeftoverOwnershipTests: XCTestCase {

    private func claims(_ name: String, id: String = "com.acme.tool",
                        installed: Set<String> = ["com.acme.tool"]) -> Bool {
        LeftoverOwnership.claims(name: name, bundleID: id, installedBundleIDs: installed)
    }

    // MARK: - The separator rule

    func testTheIdItselfIsAlwaysItsOwn() {
        XCTAssertTrue(claims("com.acme.tool"))
    }

    /// The defect, at its smallest: one character more and it is another product.
    func testALongerNameWithNoSeparatorIsADifferentApp() {
        XCTAssertFalse(claims("com.acme.toolPro"))
        XCTAssertFalse(claims("com.acme.toolbox"))
        XCTAssertFalse(claims("com.acme.tool2"))
    }

    /// What the glob is for: helpers and extensions really do hang off the id.
    func testASuffixBehindADotIsThisAppsHelper() {
        XCTAssertTrue(claims("com.acme.tool.helper"))
        XCTAssertTrue(claims("com.acme.tool.packet-extension-mac"))
    }

    /// Group containers carry a team prefix, so the id sits in the middle or at
    /// the end — the boundary rule has to hold on the left as well.
    func testATeamPrefixAheadOfADotIsStillThisApp() {
        XCTAssertTrue(claims("2XZUN9L63Z.com.acme.tool"))
        XCTAssertTrue(claims("group.com.acme.tool"))
        XCTAssertTrue(claims("2XZUN9L63Z.com.acme.tool.ext"))
    }

    /// A prefix that is not separated is a different vendor's namespace.
    func testAnUnseparatedPrefixOnTheLeftIsNotThisApp() {
        XCTAssertFalse(claims("notcom.acme.tool"))
    }

    /// macOS's own per-app file suffixes are not part of the id, and the entry
    /// under them is still this app's.
    func testKnownFileSuffixesDoNotBreakTheBoundary() {
        XCTAssertTrue(claims("com.acme.tool.plist"))
        XCTAssertTrue(claims("com.acme.tool.savedState"))
        XCTAssertTrue(claims("com.acme.tool.binarycookies"))
        // ByHost preferences carry a UUID between the id and the suffix.
        XCTAssertTrue(claims("com.acme.tool.9A8B7C6D-0000-1111-2222-333344445555.plist"))
    }

    /// And the suffix does not rescue a name that was another app's to begin
    /// with — this is the LaunchAgents shape, `"<id>*.plist"`.
    func testASuffixDoesNotLaunderASiblingsName() {
        XCTAssertFalse(claims("com.acme.toolPro.plist"))
    }

    // MARK: - The installed-set rule

    /// Vendor namespacing: `com.acme.tool.staging` passes the separator rule
    /// and is nonetheless somebody's installed app.
    func testAnInstalledNamespacedAppIsNotThisAppsLeftover() {
        XCTAssertFalse(claims("com.acme.tool.staging",
                              installed: ["com.acme.tool", "com.acme.tool.staging"]))
    }

    /// The same id with a team prefix in front of it — a group container shared
    /// by the *other* app, not by this one.
    func testAnInstalledNamespacedAppIsFoundBehindATeamPrefix() {
        XCTAssertFalse(claims("2XZUN9L63Z.com.acme.tool.staging",
                              installed: ["com.acme.tool", "com.acme.tool.staging"]))
    }

    /// The mirror of the above, and the reason the rule is "some *other*
    /// installed id", not "any installed id": the app being removed is itself
    /// installed right up until it is trashed.
    func testTheAppBeingRemovedDoesNotDisqualifyItsOwnFiles() {
        XCTAssertTrue(claims("com.acme.tool", installed: ["com.acme.tool"]))
        XCTAssertTrue(claims("com.acme.tool.helper", installed: ["com.acme.tool"]))
    }

    /// A helper that is not an app in its own right stays claimable — otherwise
    /// the glob has no reason to exist.
    func testAnUninstalledNamespacedHelperIsStillClaimed() {
        XCTAssertTrue(claims("com.acme.tool.staging", installed: ["com.acme.tool"]))
    }

    /// An unrelated installed app appearing nowhere in the name changes nothing.
    func testUnrelatedInstalledAppsAreIrrelevant() {
        XCTAssertTrue(claims("com.acme.tool.helper",
                             installed: ["com.acme.tool", "com.other.thing"]))
    }
}
