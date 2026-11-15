import Carbon.HIToolbox
import HelmRuntime
import XCTest
import Module_Screenshots_Engine
@testable import Module_Screenshots_UI

/// **The settings page weighs a shortcut against macOS's own by the pair in the store.** Absent is the shipped
/// default, a stored pair is itself, a cleared pair is nothing; key code and modifiers differ so a swap shows.
@MainActor
final class TheShortcutThePageReadsIsTheStoredPairTests: XCTestCase {
    private func store() -> NamespacedStore {
        NamespacedStore(namespace: ScreenshotsEngine.moduleID, backing: InMemoryKeyValueStore())
    }

    func testAbsentStoredAndClearedPairs() throws {
        let store = store()
        let hotkey = ScreenshotsHotkey.area
        let absent = try XCTUnwrap(ScreenshotsSettingsPage.combination(of: hotkey, in: store))
        XCTAssertEqual(absent.keyCode, hotkey.fallback.keyCode)
        XCTAssertEqual(absent.modifiers, hotkey.fallback.modifiers)

        store.set(21, for: "areaHotkeyKeyCode")
        store.set(cmdKey | optionKey, for: "areaHotkeyModifiers")
        let stored = try XCTUnwrap(ScreenshotsSettingsPage.combination(of: hotkey, in: store))
        XCTAssertEqual(stored.keyCode, 21)
        XCTAssertEqual(stored.modifiers, cmdKey | optionKey)

        store.set(-1, for: "areaHotkeyKeyCode")
        store.set(0, for: "areaHotkeyModifiers")
        XCTAssertNil(ScreenshotsSettingsPage.combination(of: hotkey, in: store))
    }
}
