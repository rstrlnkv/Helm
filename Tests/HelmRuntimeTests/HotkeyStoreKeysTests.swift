import XCTest
@testable import HelmRuntime

/// A recorded shortcut is read back from keys already on people's machines.
/// The helper that composes the names must spell exactly what was deployed.
final class HotkeyStoreKeysTests: XCTestCase {
    func testTheLayoutShortcutKeepsItsDeployedKeyNames() {
        let keys = HotkeyStoreKeys(prefix: "convertHotkey")
        XCTAssertEqual(keys.keyCode, "convertHotkeyKeyCode")
        XCTAssertEqual(keys.modifiers, "convertHotkeyModifiers")
        XCTAssertEqual(keys.label, "convertHotkeyLabel")
    }
}
