import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp
@testable import Module_Launchpad_UI

/// **Launchpad ships with no shortcut: an untouched store holds nothing, a recorded pair holds exactly that pair, and
/// a stored pair no shortcut can be made of holds nothing without trapping.** The slot and the prefix are one
/// declaration, shared by the host's registration and the page's recorder; the prefix names stored data and never moves.
@MainActor
final class ALaunchpadHotkeyHoldsNothingUntilItIsRecordedTests: XCTestCase {

    private var declared: ModuleHotkey { LaunchpadDescriptor.hotkeys[0] }

    private func combination(_ store: NamespacedStore) -> HotkeyCombination? {
        HotkeyManager.combination(store: store, prefix: declared.prefix, fallback: declared.fallback, isLive: true)
    }

    func testTheDescriptorDeclaresOneShortcutWithNoDefault() {
        XCTAssertEqual(LaunchpadDescriptor.hotkeys.count, 1)
        XCTAssertEqual(declared.slot, LaunchpadHotkey.open)
        XCTAssertEqual(declared.slot, "launchpad.open")
        XCTAssertEqual(declared.prefix, LaunchpadHotkey.storePrefix)
        XCTAssertEqual(declared.prefix, "openHotkey", "deployed stored data: a rename loses every recorded shortcut")
        XCTAssertNil(declared.fallback)
    }

    func testAnUntouchedStoreHoldsNothingAndARecordedPairHoldsThatPair() throws {
        let store = NamespacedStore.scratch()
        XCTAssertNil(combination(store))
        HelmHotkeyRecorder(store: store, prefix: declared.prefix).assign(keyCode: 37, carbonModifiers: cmdKey | optionKey, label: "⌥⌘L")
        let held = try XCTUnwrap(combination(store))
        XCTAssertEqual(Int(held.code), 37)
        XCTAssertEqual(Int(held.modifiers), cmdKey | optionKey)
    }

    func testAHostilePairHoldsNothingAndDoesNotTrap() {
        let pairs: [(Int, Int)] = [(Int.max, Int.max), (-1, 0), (0, 0), (0x100, cmdKey), (37, 0x10000), (37, 0)]
        for (key, modifiers) in pairs {
            let store = NamespacedStore.scratch(["\(declared.prefix)KeyCode": key, "\(declared.prefix)Modifiers": modifiers])
            XCTAssertNil(combination(store), "\(key), \(modifiers) was registered")
        }
    }

    func testAClearedShortcutStaysClearedAndOtherSlotsAreOtherValues() {
        let store = NamespacedStore.scratch()
        let recorder = HelmHotkeyRecorder(store: store, prefix: declared.prefix)
        recorder.assign(keyCode: 37, carbonModifiers: cmdKey, label: "⌘L")
        recorder.clear()
        XCTAssertNil(combination(store))
        XCTAssertNotEqual(LaunchpadHotkey.open, "\(LaunchpadHotkey.open).other")
        XCTAssertNotEqual(LaunchpadHotkey.storePrefix, "hotkey", "Keep Awake's prefix, in the same kind of store, would be one shortcut for two modules")
    }
}
