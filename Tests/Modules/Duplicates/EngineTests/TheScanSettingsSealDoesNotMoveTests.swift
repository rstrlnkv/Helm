import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// A rename is exactly where stored data goes missing quietly, so the keys this
/// module stores under are pinned. The strings that address the keychain item
/// live in `SettingsSealKey`; `TheRulesTheCompilerCannotHoldTests` holds that no
/// other file spells them or builds a key.
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
