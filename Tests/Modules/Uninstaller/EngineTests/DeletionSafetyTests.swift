import XCTest
import HelmRuntime
@testable import Module_Uninstaller_Engine

/// Can Helm be made to delete something it should not: an app in a subfolder
/// read as uninstalled, a hidden or crafted name, a misclassified refusal.
final class DeletionSafetyTests: XCTestCase {
    private func orphan(_ name: String, installed: Set<String> = [],
                        known: @escaping (String) -> Bool = { _ in false }) -> Bool {
        OrphanDetector.isOrphan(name: name, installedBundleIDs: installed, knownToSystem: known)
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

    /// A leading dot would walk past the skip list: `.com.apple.finder.plist`
    /// splits into three components and fails `hasPrefix("com.apple.")`.
    func testALeadingDotDoesNotSmuggleAnAppleDomainPast() {
        for name in [".com.apple.finder.plist", ".com.apple.dock.savedState"] {
            XCTAssertFalse(orphan(name), "\(name) is Apple's, dot or no dot")
        }
    }

    /// A hidden file is not evidence that its owner is gone: its id carries the
    /// dot and can never be recognised as owned.
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
    /// Access; the same code elsewhere is a plain permission problem, not a
    /// setting the person already granted.
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

    /// Unticked leftovers are not deleted just because their app is.
    func testUntickedLeftoversStay() {
        let group = UninstallGroup(
            app: InstalledApp(name: "Acme", bundleID: "com.acme",
                              path: "/Applications/Acme.app"),
            leftovers: [Leftover(path: "/keep/me", kind: .caches, sizeBytes: 9,
                                 matchedByName: false)],
            running: false)
        XCTAssertEqual(UninstallPlan.paths([group], selectedLeftovers: []),
                       ["/Applications/Acme.app"])
    }
}
