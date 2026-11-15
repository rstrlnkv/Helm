import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

/// Past defect: `UInt16(recorded)` trapped at launch on a hand-edited property
/// list value past 65535, because the key code is stored as an `Int`.
///
/// A key code past 16 bits binds nothing, as the recorder's own -1 does:
/// a chord is then not the gesture, so it drops the word before it.
final class AStoredKeyCodeCannotTrapTests: XCTestCase {
    private func activatedEngine(storing code: Int, typing: FakeTyping, tap: FakeTap) -> LayoutEngine {
        let store = layoutStore()
        store.set(code, for: "\(LayoutHotkey.storePrefix)KeyCode")
        let engine = LayoutEngine(tap: tap, typing: typing, sources: StuckSources(),
                                  translation: FakeTranslation(table: ["ghbdtn": "привет"]), spell: CyrillicSpell(),
                                  secure: FakeSecure(), activation: FakeActivation(), settings: store)
        engine.activate()
        return engine
    }

    func testAKeyCodePastWhatAKeyCanBeLeavesNoChordBound() {
        // 70000 wraps to 4464 and Int.max to 65535 if cut down to 16 bits.
        for (code, chord) in [(70000, UInt16(4464)), (Int.max, UInt16.max)] {
            let typing = FakeTyping(), tap = FakeTap()
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
        let typing = FakeTyping(), tap = FakeTap()
        let engine = activatedEngine(storing: 9, typing: typing, tap: tap)
        tap.type("ghbdtn")
        tap.send(.chord(9))
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1, "the bound chord no longer leaves the word to convert")
    }
}
