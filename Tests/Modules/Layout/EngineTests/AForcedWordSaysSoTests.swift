import HelmContract
import XCTest
@testable import Module_Layout_Engine

/// The module's promise is that typed text never reaches the disk, and the one
/// exception is «Never this word» — a button that writes `before` into the
/// stored exceptions list. For an automatic conversion that is a dictionary
/// word; for a forced one it is whatever was in front of the caret, possibly a
/// field nothing recognised as secure. The page can only decline to offer the
/// write if the event says which kind it was.
final class AForcedWordSaysSoTests: XCTestCase {

    private func engine(tap: FakeTap, automatic: Bool) -> LayoutEngine {
        let engine = LayoutEngine(
            tap: tap, typing: FakeTyping(), sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(), automatic: automatic)
        engine.activate()
        return engine
    }

    func testAForcedConversionIsMarked() async {
        let tap = FakeTap()
        let engine = engine(tap: tap, automatic: false)
        tap.type("ghbdtn"); tap.space()
        engine.convertLastWord()
        let state = await latestLayoutState(engine)
        XCTAssertEqual(state?.lastConversion?.forced, true, """
            a forced conversion reached the page unmarked: the «Never this \
            word» button will offer to write arbitrary typed text — the text \
            the dictionary refused to vouch for — into a file on disk.
            """)
        engine.deactivate()
    }

    func testAnAutomaticConversionIsNot() async {
        let tap = FakeTap()
        let engine = engine(tap: tap, automatic: true)
        tap.type("ghbdtn"); tap.space()
        let state = await latestLayoutState(engine)
        XCTAssertEqual(state?.lastConversion?.forced, false,
                       "an automatic conversion is the ordinary case, and marking it "
                       + "forced would hide the button everywhere it is safe")
        engine.deactivate()
    }
}
