import XCTest
@testable import Module_Disk_Engine

/// The gate judged the spelling, not the place: "/Users/me/Documents/.." is
/// not the string "/Users/me", so it passed every prefix test — and trashItem
/// operates on the resolved location, which is the home directory itself.
final class DiskSafetyDotDotTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func testDotDotCannotReachTheHomeDirectory() {
        XCTAssertFalse(DiskSafety.isRemovable(home + "/Documents/.."))
        XCTAssertFalse(DiskSafety.isRemovable(home + "/Documents/../."))
    }

    func testDotDotCannotReachAProtectedPrefix() {
        XCTAssertFalse(DiskSafety.isRemovable("/Users/../System/Library"))
        XCTAssertFalse(DiskSafety.isRemovable("/tmp/../usr/bin"))
    }

    func testDotDotCannotReachAVolumeRoot() {
        XCTAssertFalse(DiskSafety.isRemovable("/Volumes/Backup/x/.."))
    }

    func testAnHonestDeepPathStillPasses() {
        XCTAssertTrue(DiskSafety.isRemovable(home + "/Documents/old-report.pdf"))
    }
}
