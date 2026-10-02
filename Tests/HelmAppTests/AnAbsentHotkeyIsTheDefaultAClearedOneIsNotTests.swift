import Carbon.HIToolbox
import HelmRuntime
import HelmUI
import XCTest
@testable import HelmApp

/// **Absent and cleared are two different answers.** `HelmHotkeyRecorder.clear()`
/// writes `-1` into the store and an untouched store holds nothing at all; the
/// manager reads the first as «no shortcut» and the second as «the one the
/// module ships with». A reader that folds them can never offer a default, or
/// can never let somebody have none — and the recorder row has to draw the same
/// answer the manager registers, or it shows a shortcut that does nothing.
@MainActor
final class AnAbsentHotkeyIsTheDefaultAClearedOneIsNotTests: XCTestCase {

    private let fallback = HotkeyFallback(keyCode: 18, modifiers: cmdKey | shiftKey, label: "⇧⌘1")

    private func store(_ values: [String: Any] = [:]) -> NamespacedStore {
        let backing = InMemoryKeyValueStore()
        for (key, value) in values { backing.set(value, forKey: "module.test.\(key)") }
        return NamespacedStore(namespace: "test", backing: backing)
    }

    private func combination(_ store: NamespacedStore, fallback: HotkeyFallback? = nil,
                             isLive: Bool = true) -> HotkeyCombination? {
        HotkeyManager.combination(store: store, prefix: "hotkey", fallback: fallback, isLive: isLive)
    }

    func testAnAbsentKeyIsTheDefault() throws {
        let answer = try XCTUnwrap(combination(store(), fallback: fallback), "an untouched store registered nothing")
        XCTAssertEqual(Int(answer.code), fallback.keyCode)
        XCTAssertEqual(Int(answer.modifiers), fallback.modifiers)
    }

    func testAClearedKeyIsNotTheDefault() {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "test", backing: backing)
        let recorder = HelmHotkeyRecorder(store: store, prefix: "hotkey", fallbackLabel: fallback.label)
        XCTAssertEqual(recorder.label, "⇧⌘1", "an untouched row does not show the shortcut that is live")
        XCTAssertNotNil(combination(store, fallback: fallback))

        recorder.clear()

        XCTAssertNil(combination(store, fallback: fallback), "a shortcut somebody cleared came back as the default")
        XCTAssertEqual(recorder.label, "")
        // And a row built afterwards, as a page reopened, draws the empty one too.
        XCTAssertEqual(HelmHotkeyRecorder(store: store, prefix: "hotkey", fallbackLabel: fallback.label).label, "",
                       "a reopened page showed the default the person had cleared")
    }

    func testARecordedCombinationIsWhatWasRecorded() throws {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "test", backing: backing)
        let recorder = HelmHotkeyRecorder(store: store, prefix: "hotkey", fallbackLabel: fallback.label)
        recorder.assign(keyCode: 21, carbonModifiers: cmdKey | shiftKey, label: "⇧⌘4")
        let answer = try XCTUnwrap(combination(store, fallback: fallback))
        XCTAssertEqual(Int(answer.code), 21)
        XCTAssertEqual(Int(answer.modifiers), cmdKey | shiftKey)
        XCTAssertEqual(recorder.label, "⇧⌘4")
    }

    /// Both writers tell the host, or a recorded combination is on the page and
    /// not registered until something else happens to reload.
    func testEveryWriterTellsTheHostToRegisterAgain() {
        final class Heard: @unchecked Sendable { var count = 0 }
        let heard = Heard()
        let token = NotificationCenter.default.addObserver(forName: .helmHotkeyChanged, object: nil, queue: nil) { _ in
            heard.count += 1
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let recorder = HelmHotkeyRecorder(store: NamespacedStore(namespace: "test", backing: InMemoryKeyValueStore()),
                                          prefix: "hotkey", fallbackLabel: fallback.label)
        recorder.assign(keyCode: 21, carbonModifiers: cmdKey | shiftKey, label: "⇧⌘4")
        XCTAssertEqual(heard.count, 1, "assign() did not tell the host")
        recorder.clear()
        XCTAssertEqual(heard.count, 2, "clear() did not tell the host")
    }

    func testAModuleWithNoDefaultRegistersNothingWhenNothingWasRecorded() {
        XCTAssertNil(combination(store(), fallback: nil),
                     "a binding with no default registered a combination nobody chose")
    }

    /// The stored pair is a property-list value any process can write. Nothing
    /// the file can say reaches Carbon's conversion unbounded.
    func testAStoredPairThatIsNotACombinationIsNothing() {
        for (key, modifiers) in [(Int.max, 256), (-5, 256), (20, 0), (20, -1), (20, Int.max), (999, 256)] {
            XCTAssertNil(combination(store(["hotkeyKeyCode": key, "hotkeyModifiers": modifiers]), fallback: fallback),
                         "\(key) / \(modifiers)")
        }
    }
}
