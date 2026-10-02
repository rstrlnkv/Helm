import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **A stored shortcut Carbon cannot take is no shortcut, and the row says so.**
///
/// The preferences file is anybody's to write, and the fallback only answers
/// for a key that is *absent*: a key that is present and nonsense — a string,
/// a number past Carbon's byte, a code with its modifiers missing — reaches
/// `HotkeyCombination` and is refused there. What this adds to
/// `AnAbsentHotkeyIsTheDefaultAClearedOneIsNotTests` is the row: the recorder
/// draws `<prefix>Label`, which is a separate key, so a row can show a
/// combination the manager never registered, and pressing it does nothing.
@MainActor
final class AHotkeyTheStoreCannotSpellHoldsNothingTests: XCTestCase {

    private let fallback = HotkeyFallback(keyCode: 18, modifiers: cmdKey | shiftKey, label: "⇧⌘1")

    private func store(_ values: [String: Any]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.test.\(key)") }
        return NamespacedStore(namespace: "test", backing: backing)
    }

    private let garbage: [(String, [String: Any])] = [
        ("a string for a key code", ["hotkeyKeyCode": "twenty", "hotkeyModifiers": cmdKey | shiftKey]),
        ("a key code past Carbon's byte", ["hotkeyKeyCode": 0x1_14, "hotkeyModifiers": cmdKey | shiftKey]),
        ("the largest integer", ["hotkeyKeyCode": Int.max, "hotkeyModifiers": Int.max]),
        ("a negative modifier mask", ["hotkeyKeyCode": 20, "hotkeyModifiers": -1]),
        ("a key code with no modifiers stored", ["hotkeyKeyCode": 20]),
        ("data for a key code", ["hotkeyKeyCode": Data([20]), "hotkeyModifiers": cmdKey | shiftKey]),
    ]

    /// The manager: nothing traps, nothing is registered, and the fallback does
    /// not stand in for a key that is present.
    func testNonsenseRegistersNothingAndIsNotTheDefault() {
        for (what, values) in garbage {
            let answer = HotkeyManager.combination(store: store(values), prefix: "hotkey",
                                                   fallback: fallback, isLive: true)
            XCTAssertNil(answer, "\(what): registered \(String(describing: answer.map { ($0.code, $0.modifiers) }))")
        }
    }

    /// The row: with a label on file beside the nonsense, the row draws a
    /// combination the manager holds nothing for.
    func testTheRowDrawsNoCombinationTheManagerDoesNotHold() {
        for (what, values) in garbage {
            var withLabel = values
            withLabel["hotkeyLabel"] = "⌘⇧3"
            let store = store(withLabel)
            let registered = HotkeyManager.combination(store: store, prefix: "hotkey", fallback: fallback, isLive: true)
            let row = HelmHotkeyRecorder(store: store, prefix: "hotkey", fallbackLabel: fallback.label).label
            XCTAssertEqual(row.isEmpty, registered == nil,
                           "\(what): the row draws «\(row)» and the manager holds \(registered == nil ? "nothing" : "a key")")
        }
    }

    /// The other direction of the same rule: a pair the manager does hold, with
    /// no label on file or a label that is not a string, draws an empty row over
    /// a live shortcut — the row reads `<prefix>Label` and the manager reads the pair.
    func testTheRowDrawsTheCombinationTheManagerHolds() {
        let held: [(String, [String: Any])] = [
            ("no label on file", ["hotkeyKeyCode": 20, "hotkeyModifiers": cmdKey | shiftKey]),
            ("a number for a label", ["hotkeyKeyCode": 20, "hotkeyModifiers": cmdKey | shiftKey, "hotkeyLabel": 7]),
        ]
        for (what, values) in held {
            let store = store(values)
            let registered = HotkeyManager.combination(store: store, prefix: "hotkey", fallback: fallback, isLive: true)
            XCTAssertNotNil(registered, "\(what): the manager holds nothing, so there is no row to compare")
            let row = HelmHotkeyRecorder(store: store, prefix: "hotkey", fallbackLabel: fallback.label).label
            XCTAssertFalse(row.isEmpty, "\(what): the row is empty and the manager holds ⌘⇧3")
        }
    }

    /// What the row draws for a pair with no label is the pair, spelled the way
    /// the recorder would have spelled it: modifiers in the system's order, then
    /// the key. A stored label, when there is one, wins.
    func testTheRowSpellsAPairWithNoLabelAndKeepsAStoredOne() {
        let pair: [String: Any] = ["hotkeyKeyCode": 20, "hotkeyModifiers": cmdKey | shiftKey]
        func row(_ extra: [String: Any]) -> String {
            HelmHotkeyRecorder(store: store(pair.merging(extra) { $1 }), prefix: "hotkey",
                               fallbackLabel: fallback.label).label
        }
        XCTAssertEqual(row([:]), "⇧⌘3")
        XCTAssertEqual(row(["hotkeyLabel": 7]), "⇧⌘3")
        XCTAssertEqual(row(["hotkeyLabel": ""]), "⇧⌘3")
        XCTAssertEqual(row(["hotkeyLabel": "⌃⌥K"]), "⌃⌥K")
        XCTAssertEqual(HotkeyCombination(keyCode: 0x7F, modifiers: controlKey)?.label, "⌃#127",
                       "a code the table lacks still says that something is registered")
    }
}
