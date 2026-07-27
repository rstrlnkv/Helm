import XCTest
@testable import HelmRuntime

final class UserFileScopeTests: XCTestCase {
    func testSystemLocationsAreNeverRemovable() {
        for path in ["/System", "/System/Library/Fonts", "/usr/bin", "/bin/sh",
                     "/Library/Apple/usr", "/private/var/db/x", "/"] {
            XCTAssertFalse(UserFileScope.isRemovable(path), path)
        }
    }

    func testHomeItselfIsNotRemovableButItsContentsAre() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(UserFileScope.isRemovable(home))
        XCTAssertTrue(UserFileScope.isRemovable(home + "/Downloads/big.zip"))
    }

    /// A volume root is not removable; a folder inside it is.
    func testVolumeRootsAreProtected() {
        XCTAssertFalse(UserFileScope.isRemovable("/Volumes/Backup"))
        XCTAssertTrue(UserFileScope.isRemovable("/Volumes/Backup/old"))
    }

    /// The ring's folded bucket is an aggregate of many files, not a path.
    func testFoldedBucketIsNotRemovable() {
        XCTAssertFalse(UserFileScope.isRemovable("/Users/x/Documents/…"))
    }

    func testOrdinaryUserFilesAreRemovable() {
        XCTAssertTrue(UserFileScope.isRemovable("/Users/x/Movies/clip.mov"))
        XCTAssertTrue(UserFileScope.isRemovable("/Applications/Old.app"))
    }
}
