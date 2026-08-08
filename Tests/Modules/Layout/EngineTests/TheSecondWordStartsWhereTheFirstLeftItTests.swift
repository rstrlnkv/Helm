import XCTest
@testable import Module_Layout_Engine

/// A conversion switches the keyboard, and the next word is judged from where
/// it left it.
///
/// The engine reads `sources.current()` at the top of every conversion — it is
/// the only evidence of what the word was typed with — and `select(to)` is the
/// last thing it does. So two words in a row are two different questions:
/// `en → ru` for the first, `ru → en` for the second.
///
/// **The fake made that unrepresentable.** `FakeSources.current()` answered
/// `"en"` for ever, whatever `select()` had been told, so every test's second
/// conversion started from where its first one had. No test could have covered
/// the sequence, whatever anybody wrote — and it is the sequence a person
/// actually produces, because the whole point of switching the source is that
/// the next word is typed in the other one.
final class TheSecondWordStartsWhereTheFirstLeftItTests: XCTestCase {

    private var typing = FakeTyping()
    private var tap = FakeTap()
    private var sources = FakeSources()

    /// Both directions in the table, so the second conversion has an answer to
    /// find rather than being refused for want of one.
    private func engine() -> LayoutEngine {
        typing = FakeTyping(); tap = FakeTap(); sources = FakeSources(current: "en")
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет", "руддщ": "hello"]),
            spell: FakeSpell(valid: ["привет", "hello"]),
            secure: FakeSecure(), automatic: true)
        engine.activate()
        return engine
    }

    func testTheKeyboardIsWhereTheLastConversionPutIt() {
        let engine = engine()

        tap.type("ghbdtn"); tap.space()

        XCTAssertEqual(sources.selected, ["ru"], "precondition: the first word converted")
        XCTAssertEqual(sources.current(), "ru",
                       "the keyboard did not follow the conversion, so the next word "
                       + "is judged against a layout the person is no longer typing in")
        withExtendedLifetime(engine) {}
    }

    /// And the word after it goes back, which is the shape a person types: a
    /// mislayout, a correction, then the next mislayout the other way.
    func testTheWordAfterItIsConvertedBackTheOtherWay() {
        let engine = engine()

        tap.type("ghbdtn"); tap.space()
        tap.type("руддщ"); tap.space()

        XCTAssertEqual(sources.selected, ["ru", "en"],
                       "the second conversion did not go the other way: it was judged "
                       + "from `en` again, because that is what the source said")
        XCTAssertEqual(typing.performed.count, 2, "two replacements were expected")
        withExtendedLifetime(engine) {}
    }
}
