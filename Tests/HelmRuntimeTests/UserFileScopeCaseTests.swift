import XCTest
@testable import HelmRuntime

/// The protected list against a filesystem that does not care about case.
///
/// A prefix test reads `/system/Library/CoreServices` as another string than
/// `/System/…`, and the filesystem reads it as the same directory. The reading
/// gives a level that is there the case the disk holds; a tail that is not
/// there and a place on the list that is not on this Mac keep the case that
/// was typed, so the list is compared without regard to case. No caller spells
/// a path that way, because each passes a path it enumerated from disk, and
/// that holds only for as long as they do.
/// This file calls itself the last word on deletion for Disk, Duplicates and
/// Autopilot; the last word does not get to rely on its callers.
final class UserFileScopeCaseTests: XCTestCase {

    func testProtectedDirectoriesAreRefusedWhateverTheirCase() {
        for path in ["/system/Library/CoreServices", "/USR/bin", "/private/VAR/db/launchd.db",
                     "/Usr/Bin/perl", "/library/apple/System", "/CORES"] {
            XCTAssertFalse(UserFileScope.isRemovable(path), path)
        }
    }

    /// The two rules below the prefix list read the same string, and were
    /// case-sensitive for the same reason.
    func testAVolumeRootAndTheHomeDirectoryAreRefusedWhateverTheirCase() {
        XCTAssertFalse(UserFileScope.isRemovable("/volumes/Backup"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(UserFileScope.isRemovable(home.uppercased()))
    }

    /// Case is the only thing that changes, so an answer that changes with it
    /// is the defect — whichever way the answer goes.
    func testCaseAloneNeverChangesTheAnswer() {
        for path in UserFileScope.protectedPrefixes.map({ $0 + "/something" }) {
            XCTAssertEqual(UserFileScope.isRemovable(path),
                           UserFileScope.isRemovable(path.uppercased()),
                           path)
        }
    }

    /// The gate still has to say yes to the things it exists to allow: a rule
    /// that refuses everything passes every test above.
    func testOrdinaryUserPathsAreStillRemovable() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        for path in [home + "/Downloads/big.dmg", home + "/Library/Caches/whatever",
                     "/Users/Shared/thing.zip", "/opt/local/share/x"] {
            XCTAssertTrue(UserFileScope.isRemovable(path), path)
        }
    }
}
