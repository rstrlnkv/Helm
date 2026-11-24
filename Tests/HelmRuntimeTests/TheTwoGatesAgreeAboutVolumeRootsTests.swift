import XCTest
@testable import HelmRuntime

/// A mounted volume's own root is not somebody's app, however it is named.
///
/// `RemovableScope`'s rule is positional: a path is removable only if it sits
/// strictly inside a folder an app may leave things in. The `.app` clause comes
/// after the positional rules, so a bundle name relaxes the roots list and not
/// the rule: `/Volumes/Ext.app` is a volume root, as `UserFileScope` says too.
/// Two gates disagreeing about volume roots would let one caller offer what
/// the other refuses.
final class TheTwoGatesAgreeAboutVolumeRootsTests: XCTestCase {
    private let home = "/Users/tester"

    /// Asserted as agreement rather than as two verdicts, so the pair cannot
    /// drift apart in either direction.
    func testBothGatesRefuseAVolumeRootThatIsNamedLikeABundle() {
        let path = "/Volumes/Ext.app"
        XCTAssertEqual(RemovableScope.isRemovable(path, home: home),
                       UserFileScope.isRemovable(path),
                       "the two gates disagree about \(path)")
        XCTAssertFalse(RemovableScope.isRemovable(path, home: home))
    }

    /// A volume root under any name, and the boot volume's own top level,
    /// stated positionally rather than one string at a time.
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
