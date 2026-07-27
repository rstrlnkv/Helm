import XCTest
@testable import HelmRuntime

/// The gate judged the spelling, not the place: "/Users/me/Documents/.." is
/// not the string "/Users/me", so it passed every prefix test — and trashItem
/// operates on the resolved location, which is the home directory itself.
final class UserFileScopeDotDotTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func testDotDotCannotReachTheHomeDirectory() {
        XCTAssertFalse(UserFileScope.isRemovable(home + "/Documents/.."))
        XCTAssertFalse(UserFileScope.isRemovable(home + "/Documents/../."))
    }

    func testDotDotCannotReachAProtectedPrefix() {
        XCTAssertFalse(UserFileScope.isRemovable("/Users/../System/Library"))
        XCTAssertFalse(UserFileScope.isRemovable("/tmp/../usr/bin"))
    }

    func testDotDotCannotReachAVolumeRoot() {
        XCTAssertFalse(UserFileScope.isRemovable("/Volumes/Backup/x/.."))
    }

    func testAnHonestDeepPathStillPasses() {
        XCTAssertTrue(UserFileScope.isRemovable(home + "/Documents/old-report.pdf"))
    }
}
