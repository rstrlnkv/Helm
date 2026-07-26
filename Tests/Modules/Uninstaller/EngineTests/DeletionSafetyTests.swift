import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// Everything here answers one question: can Helm be made to delete something
/// it should not? The module has already shipped two versions of this mistake
/// — a leftovers scan that could not see apps in subfolders, and a bulk list
/// that arrived pre-ticked — so these are regressions in waiting, not theory.
final class DeletionSafetyTests: XCTestCase {
    private func orphan(_ name: String, installed: Set<String> = [],
                        known: @escaping (String) -> Bool = { _ in false }) -> Bool {
        OrphanDetector.isOrphan(name: name, installedBundleIDs: installed, knownToSystem: known)
    }

    // MARK: - Apple and the system

    func testAppleDomainsAreNeverOrphans() {
        for name in ["com.apple.Safari", "com.apple.dt.Xcode", "com.apple.finder.plist"] {
            XCTAssertFalse(orphan(name), "\(name) must never be offered")
        }
    }

    /// A vendor id that merely starts with the same letters as an installed
    /// app is a different app — but a child id of one is not.
    func testPrefixMatchingDoesNotOverreach() {
        // A real child: com.acme.tool.helper belongs to com.acme.tool.
        XCTAssertFalse(orphan("com.acme.tool.helper", installed: ["com.acme.tool"]))
        // Not a child: "com.acmetools" merely shares a prefix of characters.
        XCTAssertTrue(orphan("com.acmetools.thing", installed: ["com.acme"]))
    }

    func testAnAppInASubfolderIsNotAnOrphan() {
        XCTAssertFalse(orphan("com.adobe.Acrobat.Pro",
                              known: { $0 == "com.adobe.Acrobat.Pro" }))
    }

    // MARK: - Names that are not bundle ids

    func testOrdinaryFolderNamesAreIgnored() {
        for name in ["Downloads", "My Stuff", "notes.txt", "a.b", "", ".DS_Store"] {
            XCTAssertFalse(orphan(name), "\(name) is not a bundle id")
        }
    }

    /// The skip list is read against the id exactly as it comes off disk, so a
    /// leading dot walks straight past it: `.com.apple.finder.plist` still
    /// splits into three reverse-DNS components, still fails
    /// `hasPrefix("com.apple.")`, and arrives on the review screen as an
    /// orphan — inside `~/Library`, where `RemovableScope` allows the trash.
    /// `StaleItemRules` refuses a leading dot outright; this is the sibling
    /// rule that does not.
    func testALeadingDotDoesNotSmuggleAnAppleDomainPast() {
        for name in [".com.apple.finder.plist", ".com.apple.dock.savedState"] {
            XCTAssertFalse(orphan(name), "\(name) is Apple's, dot or no dot")
        }
    }

    /// A hidden file is not a bundle-id-shaped entry belonging to an app: the
    /// id derived from it carries the dot, matches no installed bundle id, and
    /// so can never be recognised as owned. Whatever it is, it is not evidence
    /// that its owner is gone.
    func testHiddenEntriesAreNotOrphanCandidates() {
        XCTAssertFalse(orphan(".com.vendor.tool.plist"))
    }

    /// A name crafted to look like a path must not turn into one.
    func testTraversalShapedNamesAreNotFollowed() {
        for name in ["../../etc.passwd.plist", "com.acme/../../../System"] {
            _ = orphan(name)   // must not crash or escape
        }
        XCTAssertFalse(orphan("../../etc.passwd.plist", known: { _ in true }))
    }

    // MARK: - Trash failure classification

    /// A refusal inside a container is the one case that really is Full Disk
    /// Access; the same code anywhere else is a plain permission problem, and
    /// sending someone to a setting they already granted is the bug this rule
    /// was written to end.
    func testContainerRefusalPointsAtFullDiskAccess() {
        XCTAssertEqual(TrashFailure.reason(path: "/Users/x/Library/Containers/com.acme",
                                           errorCode: 513, hasSystemExtension: false),
                       .needsFullDiskAccess)
    }

    func testTheSameCodeElsewhereIsAPlainPermissionProblem() {
        XCTAssertEqual(TrashFailure.reason(path: "/Users/x/Library/Caches/com.acme",
                                           errorCode: 513, hasSystemExtension: false),
                       .noPermission)
    }

    func testAnActiveExtensionOutranksThePermissionCode() {
        let reason = TrashFailure.reason(path: "/Applications/Acme.app",
                                         errorCode: 513, hasSystemExtension: true)
        XCTAssertEqual(reason, .activeSystemExtension)
    }

    func testAMissingFileIsNotAFailureToExplainAway() {
        let reason: TrashFailure.Reason = TrashFailure.reason(path: "/Users/x/gone",
                                                              errorCode: 4,
                                                              hasSystemExtension: false)
        XCTAssertNotEqual(reason, TrashFailure.Reason.noPermission)
    }

    // MARK: - Plans

    /// The same path reached twice — by bundle id and by app name — must be
    /// trashed once. Queuing it twice produced "failures" that were Helm's
    /// own doing: the second attempt found nothing there.
    func testAPlanNeverRepeatsAPath() {
        let path = "/Users/x/Library/Caches/com.acme"
        let duplicated = [
            Leftover(path: path, kind: .caches, sizeBytes: 10, matchedByName: false),
            Leftover(path: path, kind: .caches, sizeBytes: 10, matchedByName: true),
        ]
        let group = UninstallGroup(
            app: InstalledApp(name: "Acme", bundleID: "com.acme",
                              path: "/Applications/Acme.app", sizeBytes: 100),
            leftovers: duplicated, running: false)
        let paths = UninstallPlan.paths([group], selectedLeftovers: [path])
        XCTAssertEqual(Set(paths).count, paths.count)
        // …and the size is not counted twice either.
        XCTAssertEqual(UninstallPlan.totalBytes([group], selectedLeftovers: [path]), 110)
    }

    func testNothingToRemoveIsSaidRatherThanAssumed() {
        XCTAssertEqual(UninstallPlan.readiness([], forceQuit: false), .empty)
        XCTAssertTrue(UninstallPlan.paths([], selectedLeftovers: []).isEmpty)
    }

    /// A running app blocks removal until the user agrees to force-quit it —
    /// including when several are running.
    func testRunningAppsBlockUntilForceQuitIsAllowed() {
        let running = UninstallGroup(
            app: InstalledApp(name: "Acme", bundleID: "com.acme",
                              path: "/Applications/Acme.app", sizeBytes: 1),
            leftovers: [], running: true)
        XCTAssertEqual(UninstallPlan.readiness([running], forceQuit: false), .needsQuit(["Acme"]))
        XCTAssertEqual(UninstallPlan.readiness([running], forceQuit: true), .ready)
    }

    /// Unticked leftovers are not deleted just because their app is.
    func testUntickedLeftoversStay() {
        let group = UninstallGroup(
            app: InstalledApp(name: "Acme", bundleID: "com.acme",
                              path: "/Applications/Acme.app", sizeBytes: 1),
            leftovers: [Leftover(path: "/keep/me", kind: .caches, sizeBytes: 9,
                                 matchedByName: false)],
            running: false)
        XCTAssertEqual(UninstallPlan.paths([group], selectedLeftovers: []),
                       ["/Applications/Acme.app"])
    }
}
