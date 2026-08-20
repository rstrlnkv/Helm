import XCTest
@testable import HelmRuntime

/// A mounted volume's own root is not somebody's app, however it is named.
///
/// `RemovableScope` states its rule as positional rather than as a blocklist: a
/// path is removable only if it sits strictly inside a folder an app is allowed
/// to leave things in. The `.app` clause returned `true` before any positional
/// test could run, so a bundle name exempted a path from the whole rule — and
/// `/Volumes/Ext.app` is a **volume root**, which `UserFileScope` guards by name
/// and this gate never reached.
///
/// Reachability is thin: `trashItem` fails on a volume root, and somebody has to
/// mount an image called that. It is fixed because the gap is in the gate rather
/// than in the caller, and because two gates disagreeing about volume roots is
/// the shape that let Duplicates offer every copy of a file for removal.
///
/// The repair is ordering, not a new refusal: the positional rules move above
/// the clause, so the clause relaxes the *roots list* rather than the rule.
final class TheTwoGatesAgreeAboutVolumeRootsTests: XCTestCase {
    private let home = "/Users/tester"

    /// The measurement that opened this: one gate said yes, the other no, about
    /// the same string. Asserted as agreement rather than as two verdicts, so
    /// the pair cannot drift apart again in either direction.
    func testBothGatesRefuseAVolumeRootThatIsNamedLikeABundle() {
        let path = "/Volumes/Ext.app"
        XCTAssertEqual(RemovableScope.isRemovable(path, home: home),
                       UserFileScope.isRemovable(path),
                       "the two gates disagree about \(path)")
        XCTAssertFalse(RemovableScope.isRemovable(path, home: home))
    }

    /// A volume root under any name, and the boot volume's own top level. The
    /// `.app` clause is what let the first spelling through; the others are here
    /// so the rule is stated positionally rather than one string at a time.
    func testAVolumeRootIsNeverRemovable() {
        for path in ["/Volumes/Ext.app", "/Volumes/Backup", "/Volumes/Ext.app/",
                     "/Applications.app", "/Data.app"] {
            XCTAssertFalse(RemovableScope.isRemovable(path, home: home), path)
        }
    }

    /// And the clause still does its job: an app bundle *inside* a volume — or
    /// in any of the places people really keep apps — is the uninstaller's whole
    /// subject.
    func testAnAppInsideAVolumeIsStillRemovable() {
        for path in ["/Volumes/Ext/Acme.app", "/Volumes/Ext/Apps/Acme.app",
                     "/Applications/Acme.app", "/Users/tester/Downloads/Acme.app"] {
            XCTAssertTrue(RemovableScope.isRemovable(path, home: home), path)
        }
    }
}
