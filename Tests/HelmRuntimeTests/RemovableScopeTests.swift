import XCTest
import HelmTestSupport
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
    /// judges the name the kernel gives, where the kernel walks the `..`: a
    /// string that climbs through levels that are there is judged where it
    /// lands, which the scratch home below holds. Where a level before the
    /// `..` is not there the kernel does not walk it, the string names no
    /// place, and it is refused, which is what refuses every string here under
    /// `/Users/tester`, a home the first lines assert is not on this Mac.
    func testTraversalIsResolvedBeforeTheDecision() throws {
        var info = stat(), direct = stat()
        XCTAssertEqual(lstat("/Users/tester", &info), -1, "/Users/tester is on this Mac; the subject did not occur")
        XCTAssertFalse(removable("/Users/tester/Library/../../../System/Library"))
        XCTAssertFalse(removable("/Users/tester/Library/Caches/../../Documents/taxes.pdf"))
        XCTAssertFalse(removable("/Applications/Acme.app/../../System"))

        // The same trick that lands back inside the scope is still inside it,
        // where every level it climbs through is there: a scratch home that
        // has them, and the kernel's own `stat` of the typed string as proof.
        let scratch = scratchDirectory("traversal")
        let preference = scratch.appendingPathComponent("Library/Preferences/com.acme.plist")
        try FileManager.default.createDirectory(at: preference.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scratch.appendingPathComponent("Library/Caches"), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: preference.path, contents: Data("x".utf8)))
        let walked = scratch.path + "/Library/Caches/../Preferences/com.acme.plist"
        XCTAssertEqual(lstat(walked, &info), 0, "the kernel does not walk \(walked); the subject did not occur")
        XCTAssertEqual(lstat(preference.path, &direct), 0)
        XCTAssertEqual(info.st_ino, direct.st_ino, "\(walked) is not the preference file; the subject did not occur")
        XCTAssertTrue(RemovableScope.isRemovable(preference.path, home: scratch.path), "CONTROL: the file by its own name")
        XCTAssertTrue(RemovableScope.isRemovable(walked, home: scratch.path), "\(walked) is refused, and the kernel walks it into the scope")

        // A level before the `..` that is not there: the kernel stops, the
        // letters would have folded it back into the scope.
        let missing = scratch.path + "/Library/Caches/Absent/../Preferences/com.acme.plist"
        XCTAssertEqual(lstat(missing, &info), -1)
        XCTAssertEqual(errno, ENOENT, "the kernel walks \(missing); the subject did not occur")
        XCTAssertFalse(RemovableScope.isRemovable(missing, home: scratch.path), "\(missing) is accepted, and the kernel does not walk it")
        // And the home that is not on this Mac: nothing in the string is there to walk.
        XCTAssertFalse(removable("/Users/tester/Library/Caches/../Preferences/com.acme.plist"))
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
