import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// An undo is the person saying «I meant what I typed» — and what they typed
/// was typed on the layout the conversion just switched away from.
///
/// `convert` does two things on success: it retypes the word and it calls
/// `sources.select(to)`, because the person who mistyped `ghbdtn` is about to
/// continue in Russian. The undo takes back both: rebuilding only the text
/// would leave the keyboard on the rejected layout, and every keystroke after
/// it would come out Cyrillic, the very thing this module exists to fix.
final class TheUndoPutsTheKeyboardBackTests: XCTestCase {

    func testUndoPutsTheKeyboardBackWhereTheWordWasTyped() {
        let typing = FakeTyping()
        let tap = FakeTap()
        let sources = FakeSources(current: "en")
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(), activation: FakeActivation(), automatic: true)
        engine.activate()

        tap.type("ghbdtn"); tap.space()
        XCTAssertEqual(sources.current(), "ru",
                       "precondition: the conversion switched the keyboard, or there is "
                       + "nothing to put back")

        engine.undoLast()
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn ",
                       "precondition: the undo happened — without it the source assertion "
                       + "below would be about nothing")
        XCTAssertEqual(sources.current(), "en", """
            the undo put the text back and left the keyboard on the layout of the \
            conversion it just rejected: the next word the person types comes out in \
            the wrong alphabet, which is the mistake this module exists to fix.
            """)
        engine.deactivate()
    }
}
