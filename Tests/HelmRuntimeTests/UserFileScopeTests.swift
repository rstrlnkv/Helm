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

    /// **This gate judges no names.** It used to refuse any path ending in `/…`
    /// — the disk module's folded bucket wore that name, and refusing it here
    /// was how the aggregate was kept out of the basket. `…` is a name a person
    /// can type and Finder accepts, so the rule refused their own file with it:
    /// drawn as a system item, no basket button, nothing saying why. The bucket
    /// is `DiskNode.isFolded` now and is told apart by the flag at the row, in
    /// the basket and in `DiskRemovalPlan` — none of which a filename can reach.
    func testAFileNamedLikeTheRingsFoldedBucketIsStillTheUsersOwnFile() {
        XCTAssertTrue(UserFileScope.isRemovable("/Users/x/Documents/…"))
    }

    /// Screenshots is this gate's caller since «Edit» replaces the file a shot wrote: the original goes to the Trash
    /// from where the module saves, which is the Desktop, Documents or a folder the person chose.
    func testAScreenshotOnTheDesktopAndInAChosenFolderIsTheUsersOwnFile() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertTrue(UserFileScope.isRemovable(home + "/Desktop/Screenshot 2026-10-02 at 18.00.00.png"))
        XCTAssertTrue(UserFileScope.isRemovable(home + "/Documents/Screenshot 2026-10-02 at 18.00.00.jpg"))
        XCTAssertTrue(UserFileScope.isRemovable(home + "/Pictures/Shots/Screenshot 2026-10-02 at 18.00.00 (1).png"))
        XCTAssertTrue(UserFileScope.isRemovable("/Volumes/Work/Shots/Screenshot 2026-10-02 at 18.00.00.png"))
    }

    func testOrdinaryUserFilesAreRemovable() {
        XCTAssertTrue(UserFileScope.isRemovable("/Users/x/Movies/clip.mov"))
        XCTAssertTrue(UserFileScope.isRemovable("/Applications/Old.app"))
    }
}
