import XCTest
@testable import HelmRuntime

/// `RemovableScope` is the last word before `trashItem` for both the
/// uninstaller and the leftovers module, and it had no tests of its own —
/// every assertion about it lived one layer up, in a view model's rules.
/// These pin the gate itself: what it lets through, and what it must refuse
/// however the caller spells the path.
final class RemovableScopeTests: XCTestCase {
    private let home = "/Users/tester"

    private func removable(_ path: String) -> Bool {
        RemovableScope.isRemovable(path, home: home)
    }

    // MARK: - What an app is allowed to leave behind

    func testFilesInsideAnAppsOwnFoldersAreRemovable() {
        for path in ["/Users/tester/Library/Preferences/com.acme.tool.plist",
                     "/Users/tester/Library/Containers/com.acme.tool",
                     "/Users/tester/Library/Application Support/Acme",
                     "/Library/LaunchDaemons/com.acme.daemon.plist",
                     "/Library/PrivilegedHelperTools/com.acme.helper"] {
            XCTAssertTrue(removable(path), path)
        }
    }

    /// An app bundle names itself, wherever the user keeps it.
    func testAppBundlesAreRemovableOutsideApplications() {
        XCTAssertTrue(removable("/Applications/Acme.app"))
        XCTAssertTrue(removable("/Users/tester/Downloads/Acme.app"))
        XCTAssertTrue(removable("/Volumes/Ext/Acme.app"))
    }

    // MARK: - The containers themselves are not the contents

    /// The roots are folders whose *contents* belong to apps. Handing the gate
    /// the root itself — which is what an empty or truncated candidate degrades
    /// into — must not be how `~/Library` goes to the Trash.
    func testTheContainingFoldersAreNeverRemovable() {
        for path in ["/Users/tester/Library", "/Applications", "/Library/Caches",
                     "/Library/LaunchAgents", "/Users/tester", "/Users", "/"] {
            XCTAssertFalse(removable(path), path)
        }
    }

    func testUserDataOutsideAnAppsFoldersIsRefused() {
        for path in ["/Users/tester/Documents/taxes.pdf",
                     "/Users/tester/Desktop",
                     "/Users/tester/.ssh/id_ed25519"] {
            XCTAssertFalse(removable(path), path)
        }
    }

    /// Another account's files are inside *a* home's Library, not this one's.
    func testAnotherUsersLibraryIsRefused() {
        XCTAssertFalse(removable("/Users/someone-else/Library/Preferences/com.acme.plist"))
    }

    // MARK: - Apple's own, and the way out of a folder

    func testAppleOwnedLocationsAreRefusedEvenInsideAnAllowedRoot() {
        for path in ["/Library/Apple/System/Library/CoreServices",
                     "/System/Library/Fonts",
                     "/Applications/Utilities",
                     "/Applications/Utilities/Terminal.app"] {
            XCTAssertFalse(removable(path), path)
        }
    }

    /// `..` is invisible to a prefix test and not to `trashItem`, so the gate
    /// resolves before it compares. A candidate that climbs out of the folder
    /// it was scoped to is judged where it actually lands.
    func testTraversalIsResolvedBeforeTheDecision() {
        XCTAssertFalse(removable("/Users/tester/Library/../../../System/Library"))
        XCTAssertFalse(removable("/Users/tester/Library/Caches/../../Documents/taxes.pdf"))
        XCTAssertFalse(removable("/Applications/Acme.app/../../System"))
        // The same trick that lands back inside the scope is still inside it.
        XCTAssertTrue(removable("/Users/tester/Library/Caches/../Preferences/com.acme.plist"))
    }

    // MARK: - Partition reports refusals instead of dropping them

    func testPartitionKeepsEveryPathAndItsOrder() {
        let paths = ["/Applications/Acme.app", "/Users/tester/Documents/taxes.pdf",
                     "/Users/tester/Library/Caches/com.acme", "/System"]
        let (allowed, refused) = RemovableScope.partition(paths, home: home)
        XCTAssertEqual(allowed, ["/Applications/Acme.app",
                                 "/Users/tester/Library/Caches/com.acme"])
        XCTAssertEqual(refused, ["/Users/tester/Documents/taxes.pdf", "/System"])
        XCTAssertEqual(allowed.count + refused.count, paths.count,
                       "a refusal must be reported, never dropped")
    }
}
