import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// `guardOfFolder` became `guardOfScanSettings` when the keep policy joined the
/// folder under it, and a rename is exactly where stored data goes missing
/// quietly.
///
/// What is left here is what is this module's own. The three strings that address
/// the keychain item, and the single cache in front of it, moved to
/// `SettingsSealKey` with the item itself; `TheRulesTheCompilerCannotHoldTests`
/// holds that no other file spells them or builds a key.
final class TheScanSettingsSealDoesNotMoveTests: XCTestCase {

    /// The store keys are stored data too, and the MAC's spelling is derived
    /// from the value's rather than written twice. Recorded as the literals that
    /// shipped: deriving both sides here would be a test whose two halves read
    /// one constant, which cannot fail.
    func testTheStoredKeysAreTheOnesAlreadyOnPeoplesMacs() {
        XCTAssertEqual(DuplicatesSettings.keepPolicyKey, "keepPolicy")
        XCTAssertEqual(DuplicatesSettings.folderKey, "folder")
        XCTAssertEqual(SettingGuard.macKey(for: "folder"), "folderMAC")
        XCTAssertEqual(SettingGuard.macKey(for: DuplicatesSettings.keepPolicyKey),
                       "keepPolicyMAC")
    }
}
