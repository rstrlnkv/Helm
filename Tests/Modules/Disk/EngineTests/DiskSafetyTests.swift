import XCTest
@testable import Module_Disk_Engine

final class DiskSafetyTests: XCTestCase {
    func testSystemLocationsAreNeverRemovable() {
        for path in ["/System", "/System/Library/Fonts", "/usr/bin", "/bin/sh",
                     "/Library/Apple/usr", "/private/var/db/x", "/"] {
            XCTAssertFalse(DiskSafety.isRemovable(path), path)
        }
    }

    func testHomeItselfIsNotRemovableButItsContentsAre() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertFalse(DiskSafety.isRemovable(home))
        XCTAssertTrue(DiskSafety.isRemovable(home + "/Downloads/big.zip"))
    }

    /// A volume root is not removable; a folder inside it is.
    func testVolumeRootsAreProtected() {
        XCTAssertFalse(DiskSafety.isRemovable("/Volumes/Backup"))
        XCTAssertTrue(DiskSafety.isRemovable("/Volumes/Backup/old"))
    }

    /// The ring's folded bucket is an aggregate of many files, not a path.
    func testFoldedBucketIsNotRemovable() {
        XCTAssertFalse(DiskSafety.isRemovable("/Users/x/Documents/…"))
    }

    func testOrdinaryUserFilesAreRemovable() {
        XCTAssertTrue(DiskSafety.isRemovable("/Users/x/Movies/clip.mov"))
        XCTAssertTrue(DiskSafety.isRemovable("/Applications/Old.app"))
    }
}
