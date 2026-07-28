import XCTest
@testable import HelmRuntime

/// The disk module's last word on deletion, against the one directory on the
/// list that has two spellings.
///
/// `isRemovable` standardizes before it tests, and `NSString.standardizingPath`
/// does not only remove `.` and `..`: for a path that **exists on disk** it also
/// rewrites `/private/var/...` to `/var/...`. `protectedPrefixes` names
/// `/private/var/db`, so the rewrite lands the path outside every prefix on the
/// list and the gate lets it through.
///
/// The existing coverage tests `/private/var/db/x`, which does not exist — so it
/// is never rewritten, and the assertion passes on the one spelling nobody can
/// reach. Every real path there takes the other branch.
final class UserFileScopePrivateVarTests: XCTestCase {

    /// The two names of one directory must get one answer. `/var` *is*
    /// `/private/var`; the list names the long spelling and the gate is handed
    /// the short one.
    func testBothSpellingsOfTheSameProtectedDirectoryAgree() {
        for pair in [("/private/var/db", "/var/db"),
                     ("/private/var/db/dslocal", "/var/db/dslocal")] {
            XCTAssertEqual(UserFileScope.isRemovable(pair.0),
                           UserFileScope.isRemovable(pair.1),
                           "\(pair.0) and \(pair.1) are the same directory")
            XCTAssertFalse(UserFileScope.isRemovable(pair.1),
                           "\(pair.1) is \(pair.0), which the protected list names")
        }
    }

    /// A prefix on the list has to refuse the paths that are actually under it,
    /// not only the ones that are not there. Anything on the list that exists is
    /// checked against itself and against its real children.
    func testEveryProtectedPrefixRefusesPathsThatReallyExist() {
        let fm = FileManager.default
        for prefix in UserFileScope.protectedPrefixes where fm.fileExists(atPath: prefix) {
            XCTAssertFalse(UserFileScope.isRemovable(prefix), prefix)
            let children = (try? fm.contentsOfDirectory(atPath: prefix)) ?? []
            for child in children.sorted().prefix(4) {
                let path = prefix + "/" + child
                XCTAssertFalse(UserFileScope.isRemovable(path), path)
            }
        }
    }
}
