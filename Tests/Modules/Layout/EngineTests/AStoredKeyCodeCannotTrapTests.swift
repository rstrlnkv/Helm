import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

private final class KeyTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private struct KeyContext: SecureContextPort {
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { "com.apple.Notes" }
}

private struct KeyTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        word == "ghbdtn" ? "привет" : nil
    }
}

private struct KeySpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class KeyTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        handler = onEvent
        return true
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
}

private struct KeySources: LayoutSourcePort {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

/// Past defect: `UInt16(recorded)` trapped at launch on a hand-edited property
/// list value past 65535, because the key code is stored as an `Int`.
///
/// A key code past 16 bits binds nothing, as the recorder's own -1 does:
/// a chord is then not the gesture, so it drops the word before it.
final class AStoredKeyCodeCannotTrapTests: XCTestCase {
    private func activatedEngine(storing code: Int, typing: KeyTyping, tap: KeyTap) -> LayoutEngine {
        let store = NamespacedStore(namespace: LayoutEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        store.set(code, for: "\(LayoutHotkey.storePrefix)KeyCode")
        let engine = LayoutEngine(tap: tap, typing: typing, sources: KeySources(),
                                  translation: KeyTranslation(), spell: KeySpell(),
                                  secure: KeyContext(), activation: FakeActivation(), settings: store)
        engine.activate()
        return engine
    }

    func testAKeyCodePastWhatAKeyCanBeLeavesNoChordBound() {
        // 70000 wraps to 4464 and Int.max to 65535 if cut down to 16 bits.
        for (code, chord) in [(70000, UInt16(4464)), (Int.max, UInt16.max)] {
            let typing = KeyTyping(), tap = KeyTap()
            let engine = activatedEngine(storing: code, typing: typing, tap: tap)
            tap.type("ghbdtn")
            tap.send(.chord(chord))
            engine.convertLastWord()
            XCTAssertTrue(typing.performed.isEmpty,
                          "\(code) bound a chord: the word survived a chord that is not the gesture")
        }
    }

    /// A value a key can have still binds, as it did before.
    func testAKeyCodeInRangeStillBinds() {
        let typing = KeyTyping(), tap = KeyTap()
        let engine = activatedEngine(storing: 9, typing: typing, tap: tap)
        tap.type("ghbdtn")
        tap.send(.chord(9))
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1, "the bound chord no longer leaves the word to convert")
    }
}
