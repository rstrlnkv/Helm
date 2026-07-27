import XCTest
@testable import HelmRuntime

/// `UserFileScope.isRemovable` is the whole gate for the disk module: the view
/// model consults it before adding to the basket, and `DiskEngine.trash`
/// re-checks it before calling `trashItem`. Nothing else stands between a
/// clicked ring segment and the Trash.
///
/// It refuses `/` and it refuses a volume root, so the rule "a mount's own
/// top-level directory is not a thing to delete" is already understood here —
/// and `RemovableScope` states it outright ("not a top-level directory"). The
/// boot volume's own top level is the case that falls through: scan `/`, click
/// the second-largest arc, and `/Users` goes in the basket.
final class UserFileScopeTopLevelTests: XCTestCase {
    /// Every one of these is a first-level directory of the boot volume whose
    /// removal is not a cleanup but an outage. `/System`, `/usr`, `/bin`,
    /// `/sbin` and `/cores` are already named in `protectedPrefixes`; these are
    /// their neighbours in the same listing.
    func testTopLevelDirectoriesOfTheBootVolumeAreNotRemovable() {
        for path in ["/Users", "/Library", "/Applications", "/private",
                     "/Volumes", "/Network", "/opt"] {
            XCTAssertFalse(UserFileScope.isRemovable(path),
                           "\(path) is the top level of the boot volume, not a cleanup target")
        }
    }

    /// The guard above must not be bought by refusing everything: what is
    /// inside those directories is exactly what the module is for.
    func testWhatSitsInsideThemStaysRemovable() {
        for path in ["/Users/x/Movies", "/Library/Caches", "/Applications/Old.app",
                     "/private/tmp/build", "/opt/local"] {
            XCTAssertTrue(UserFileScope.isRemovable(path), path)
        }
    }
}
