import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// What the two classes below read from a store they cannot spell: the shortcut an absent key falls back to,
/// and the values that are present and nonsense. No tests of its own.
@MainActor
class HotkeyGarbageFixture: XCTestCase {

    let fallback = HotkeyFallback(keyCode: 18, modifiers: cmdKey | shiftKey, label: "⇧⌘1")

    let garbage: [(String, [String: Any])] = [
        ("a string for a key code", ["hotkeyKeyCode": "twenty", "hotkeyModifiers": cmdKey | shiftKey]),
        ("a key code past Carbon's byte", ["hotkeyKeyCode": 0x1_14, "hotkeyModifiers": cmdKey | shiftKey]),
        ("the largest integer", ["hotkeyKeyCode": Int.max, "hotkeyModifiers": Int.max]),
        ("a negative modifier mask", ["hotkeyKeyCode": 20, "hotkeyModifiers": -1]),
        ("a key code with no modifiers stored", ["hotkeyKeyCode": 20]),
        ("data for a key code", ["hotkeyKeyCode": Data([20]), "hotkeyModifiers": cmdKey | shiftKey]),
    ]
}

/// **A stored shortcut Carbon cannot take is no shortcut.**
///
/// The preferences file is anybody's to write, and the fallback only answers
/// for a key that is *absent*: a key that is present and nonsense — a string,
/// a number past Carbon's byte, a code with its modifiers missing — reaches
/// `HotkeyCombination` and is refused there.
@MainActor
final class AHotkeyTheStoreCannotSpellHoldsNothingTests: HotkeyGarbageFixture {

    /// The manager: nothing traps, nothing is registered, and the fallback does
    /// not stand in for a key that is present.
    func testNonsenseRegistersNothingAndIsNotTheDefault() {
        for (what, values) in garbage {
            let answer = HotkeyManager.combination(store: NamespacedStore.scratch(values), prefix: "hotkey",
                                                   fallback: fallback, isLive: true)
            XCTAssertNil(answer, "\(what): registered \(String(describing: answer.map { ($0.code, $0.modifiers) }))")
        }
    }
}
