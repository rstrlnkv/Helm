import XCTest
@testable import Module_Uninstaller_Engine

/// The rule behind the glob filter, on its own.
///
/// `GlobMatch` answers a question about text; this guards whether the entry
/// that matched is this app's. `com.acme.tool*` matches `com.acme.toolPro` as
/// well as `com.acme.tool.helper`, and only one is the app being removed. The
/// rules are in `LeftoverOwnership.swift`.
final class LeftoverOwnershipTests: XCTestCase {

    /// `known` is what LaunchServices answers, the apps a directory listing
    /// cannot see. Empty means "the listing is the whole truth".
    private func claims(_ name: String, id: String = "com.acme.tool",
                        installed: Set<String> = ["com.acme.tool"],
                        known: Set<String> = [],
                        installedPaths: [String] = ["/Applications/Tool.app"]) -> Bool {
        LeftoverOwnership(bundleID: id, installedBundleIDs: installed,
                          installedPaths: installedPaths,
                          knownToSystem: { known.contains($0) })
            .claims(name: name)
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

    /// The rule is "some other installed id": the app being removed is itself
    /// installed until it is trashed.
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

    // MARK: - The apps the listing cannot see

    /// An app nested in another bundle, or deeper than the listing's two levels,
    /// is installed and absent from `installedBundleIDs()`; LaunchServices is the
    /// only witness.
    func testAnAppTheListingCannotSeeIsStillNotThisAppsLeftover() {
        XCTAssertFalse(claims("com.acme.tool.staging",
                              installed: ["com.acme.tool"],
                              known: ["com.acme.tool.staging"]))
    }

    /// A group container carries a team or `group.` prefix, so the id to ask
    /// about is the one *inside* the name, not the name.
    func testANestedAppIsFoundBehindATeamPrefix() {
        XCTAssertFalse(claims("group.com.acme.tool.staging",
                              installed: ["com.acme.tool"], known: ["com.acme.tool.staging"]))
        XCTAssertFalse(claims("2XZUN9L63Z.com.acme.tool.staging",
                              installed: ["com.acme.tool"], known: ["com.acme.tool.staging"]))
    }

    /// The LaunchAgents shape: macOS's own file suffix is not part of the id,
    /// and trashing this one stops the neighbour's updater for good.
    func testANestedAppIsFoundUnderAFileSuffix() {
        XCTAssertFalse(claims("com.acme.tool.staging.plist",
                              installed: ["com.acme.tool"], known: ["com.acme.tool.staging"]))
    }

    /// What hangs off an installed app goes with it: the id in the middle of
    /// the name is the one somebody has installed, so the helper's container is
    /// that app's problem, not this one's.
    func testAHelperOfAnAppTheListingCannotSeeGoesWithIt() {
        XCTAssertFalse(claims("com.acme.tool.staging.helper",
                              installed: ["com.acme.tool"], known: ["com.acme.tool.staging"]))
    }

    /// The app being removed is installed and known right up until it is
    /// trashed, which must not disqualify its own files.
    func testTheAppBeingRemovedIsNotItsOwnRival() {
        XCTAssertTrue(claims("com.acme.tool", known: ["com.acme.tool"]))
        XCTAssertTrue(claims("com.acme.tool.helper", known: ["com.acme.tool"]))
    }

    /// Which questions get asked: a LaunchServices lookup only about this id
    /// extended past a dot, never about `group.`, a team prefix, or this id.
    func testItAsksOnlyAboutIdsThatExtendThisOne() {
        var asked: [String] = []
        _ = LeftoverOwnership(bundleID: "com.acme.tool",
                              installedBundleIDs: ["com.acme.tool"],
                              installedPaths: ["/Applications/Tool.app"],
                              knownToSystem: { asked.append($0); return false })
            .claims(name: "group.com.acme.tool.staging.helper")
        XCTAssertEqual(Set(asked), ["com.acme.tool.staging", "com.acme.tool.staging.helper"])
    }

    // MARK: - Whose id is it

    /// The id is read from the app's own `Info.plist`, where any app may write
    /// anybody's, and the exact candidates (`Containers/<id>`) arrive pre-ticked.
    /// Two installed bundles declaring one id claim nothing, impostor or honest
    /// second copy: the data belongs to something that stays installed.
    func testAnIdTwoInstalledBundlesDeclareClaimsNothing() {
        let both = ["/Applications/Tool.app", "/Applications/Sketchy.app"]
        XCTAssertFalse(claims("com.acme.tool", installedPaths: both))
        XCTAssertFalse(claims("com.acme.tool.plist", installedPaths: both))
        XCTAssertFalse(claims("com.acme.tool.helper", installedPaths: both))
        XCTAssertFalse(claims("group.com.acme.tool", installedPaths: both))
    }

    /// The ordinary case: one bundle declares it, and it is the one on its way
    /// to the trash.
    func testOneInstalledBundleIsTheAppBeingRemoved() {
        XCTAssertTrue(claims("com.acme.tool", installedPaths: ["/Applications/Tool.app"]))
    }

    /// One bundle named twice is one bundle: a lister answering from two sources
    /// reports the same path twice, and a rival there would silence every scan.
    func testOneBundleReportedTwiceIsStillOneApp() {
        XCTAssertTrue(claims("com.acme.tool",
                             installedPaths: ["/Applications/Tool.app", "/Applications/Tool.app"]))
    }

    /// An empty answer is not evidence of a rival — a lister that knows nothing
    /// must not refuse everything.
    func testKnowingOfNoInstalledBundleRefusesNothing() {
        XCTAssertTrue(claims("com.acme.tool", installedPaths: []))
    }

    /// A name that is not this app's at all is refused before anything is
    /// asked: the separator rule is cheaper than a LaunchServices round trip.
    func testANameThatIsNotThisAppsAsksNothing() {
        var asked: [String] = []
        _ = LeftoverOwnership(bundleID: "com.acme.tool",
                              installedBundleIDs: ["com.acme.tool"],
                              installedPaths: ["/Applications/Tool.app"],
                              knownToSystem: { asked.append($0); return false })
            .claims(name: "com.acme.toolPro")
        XCTAssertEqual(asked, [])
    }
}
