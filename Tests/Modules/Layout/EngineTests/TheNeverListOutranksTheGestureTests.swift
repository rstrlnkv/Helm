import XCTest
@testable import Module_Layout_Engine

/// «Never change these words» has no footnote. The list's own header is
/// absolute, and the force path — the gesture, the hotkey — used to skip it:
/// the one word somebody wrote down as untouchable was still one stray tap away
/// from being rewritten. Whoever really wants the conversion removes the word
/// from the list; the module does not decide the header meant less than it says.
final class TheNeverListOutranksTheGestureTests: XCTestCase {

    private func engine(exceptions: [String],
                        typing: FakeTyping, tap: FakeTap) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(),
            exceptions: exceptions,
            automatic: false)
        engine.activate()
        return engine
    }

    func testAForcedConversionRespectsTheList() {
        let typing = FakeTyping()
        let tap = FakeTap()
        let engine = engine(exceptions: ["ghbdtn"], typing: typing, tap: tap)

        tap.type("ghbdtn"); tap.space()
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            the word is on the «Never change these words» list and the gesture \
            converted it anyway: the list's own header is absolute, and the one \
            path that ignored it is the one a stray tap fires.
            """)
        engine.deactivate()
    }

    /// The same rule the automatic path applies: somebody tired of a word keeps
    /// typing the form they keep *seeing*, which is the converted one.
    func testTheConvertedFormOfTheWordCountsToo() {
        let typing = FakeTyping()
        let tap = FakeTap()
        let engine = engine(exceptions: ["привет"], typing: typing, tap: tap)

        tap.type("ghbdtn"); tap.space()
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            the list entry names the converted form and the gesture converted \
            into it anyway — the automatic path checks both forms for exactly \
            this reason, and the forced one answered to neither.
            """)
        engine.deactivate()
    }
}
