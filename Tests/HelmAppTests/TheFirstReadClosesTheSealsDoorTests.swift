import HelmRuntime
import HelmTestSupport
import XCTest
@testable import HelmApp

/// The one door the seal leaves open, and who walks through it.
///
/// `SettingSeal.verdict` adopts an unsealed value when `key.firstUse` is true,
/// which is true only on the run that creates the keychain item. A getter that
/// returned the default *before* touching the guard would leave first use
/// unspent, and the first value anybody wrote would be adopted and sealed as
/// Helm's own. `defaults write com.helm.app module.app.disabledScans -array`
/// would be the whole attack: a full-volume walk under Helm's Full Disk Access.
@MainActor
final class TheFirstReadClosesTheSealsDoorTests: DisabledScansTestCase {

    func testReadingTheDefaultCreatesThisInstallationsKey() {
        let keychain = freshMac()
        XCTAssertEqual(AppSettings.disabledScans, ["disk"], "the default is still the default")
        XCTAssertGreaterThan(keychain.reads, 0,
                             "the first read must create the key, or first use stays unspent")
    }

    /// The harm, end to end: Helm reads its own default on day one, something
    /// else writes the plist afterwards, and that value is not Helm's.
    func testAValueWrittenAfterHelmsFirstReadIsNotAdopted() {
        _ = freshMac()
        _ = AppSettings.disabledScans                      // day one, nothing stored

        AppSettings.store.set([String](), for: key)        // "scan everything", unsigned
        // Assert the subject happened: the plist really does hold that value now.
        XCTAssertEqual(AppSettings.store.object(key) as? [String], [])

        XCTAssertEqual(AppSettings.disabledScans, Set(ScanRunner.scannableModules),
                       "an unsealed value arriving after day one is refused, not adopted")
    }

    /// And the reverse is still true: a value Helm itself wrote reads back.
    func testWhatHelmWroteAfterThatFirstReadIsStillItsOwn() {
        _ = freshMac()
        _ = AppSettings.disabledScans
        AppSettings.disabledScans = ["disk", "duplicates"]
        XCTAssertEqual(AppSettings.disabledScans, ["disk", "duplicates"])
    }
}
