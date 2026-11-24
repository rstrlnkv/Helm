import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

/// The convert half of a caret move; `UndoAfterNavigationTests` holds the undo
/// half.
///
/// With no undo record to spend, `fix()` falls through to `convertLastWord()`,
/// which reaches for `lastCompleted`, the word that most recently ended.
/// `handle()` clears it whenever `movedTheCaret` is true (`.navigation` and
/// `.click`), the same check `UndoRecord` makes.
///
/// The sequence, in a person's terms: type `ghbdtn` at the end of a paragraph,
/// notice a typo three lines up, press ← to go and fix it, tap the bound
/// modifier out of habit — and six backspaces and a Russian word land three
/// lines up, in text the module never watched being typed.
///
/// `convertLastWord()` rather than `fix()`: `fix()` hops to a global queue and
/// back to main for the accessibility probe, and a test that waits on that is a
/// test about scheduling. This is the same door, taken synchronously.
final class GestureAfterNavigationTests: XCTestCase {
    private var typing = FakeTyping()
    private var context = FakeSecure()
    private var tap = FakeTap()

    private func engine() -> LayoutEngine {
        typing = FakeTyping(); context = FakeSecure(); tap = FakeTap()
        let store = layoutStore(bound: true)
        let engine = LayoutEngine(tap: tap, typing: typing, sources: FakeSources(follows: false),
                                  translation: FakeTranslation(table: ["ghbdtn": "привет"]), spell: FakeSpell(cyrillic: true),
                                  secure: context, activation: FakeActivation(), settings: store)
        engine.activate()
        return engine
    }

    // MARK: - The caret moved

    /// One Left Arrow, and the word before it is not the gesture's to convert.
    func testAnArrowKeyEndsTheGesturesClaimOnTheWord() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.navigation)          // ←, and nothing else

        engine.convertLastWord()

        XCTAssertTrue(typing.performed.isEmpty,
                      "the gesture sent \(typing.performed.first?.backspaces ?? 0) backspaces "
                      + "at a caret the arrow key had already moved")
    }

    /// `handle()` overwrites the remembered word with `finished.map { … }` on
    /// most events, so a second event with nothing to finish clears it by
    /// accident. The window is the caret move being the most recent thing, which
    /// is the shape of the gesture: press ↑ or Home or Escape, then tap the key.
    ///
    /// This asserts the accident, so a change that merely reorders `handle()`
    /// cannot be mistaken for one that clears the field.
    func testASecondEventHidesTheWordOnlyByAccident() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.navigation)
        tap.send(.navigation)          // nothing left to finish, so nil is stored

        engine.convertLastWord()

        XCTAssertTrue(typing.performed.isEmpty)
    }

    /// The fix must not be "stop ending the word at a caret move".
    ///
    /// `.navigation` has to keep ending the word — the buffer is what is
    /// adjacent to the caret, and text three lines up is not — so the boundary
    /// itself is pinned here, separately from what is remembered across it.
    func testACaretMoveStillEndsTheWordInTheBuffer() {
        var buffer = TypingBuffer()
        for character in "ghbdtn" { buffer.accept(.character(character)) }

        let completion = buffer.accept(.navigation)

        XCTAssertEqual(completion?.word, "ghbdtn", "the caret move stopped ending the word")
        XCTAssertNil(completion?.ending, "a caret move typed a character into the field")
        XCTAssertNil(buffer.wholeWord, "the word stayed in the buffer past the caret move")
    }

    /// The undo half, unchanged, asserted here so a fix to the convert half
    /// cannot be made by re-opening the one that is already closed.
    func testTheUndoHalfIsStillClosed() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.space)               // converted; there is an undo record now
        XCTAssertEqual(typing.performed.count, 1, "precondition: the word was converted")

        tap.send(.navigation)
        engine.undoLast()

        XCTAssertEqual(typing.performed.count, 1)
    }

    // MARK: - …and the gesture still works where it should

    /// The control that stops "refuse everything" from passing the tests above.
    /// The **shortcut's own chord** is the one boundary that is not proof the
    /// caret moved — its keys reach the tap before Carbon dispatches the action
    /// — so a word ended by it is still the gesture's to convert.
    ///
    /// Only that chord: ⌘V changes the text in front of the caret.
    /// `UndoAfterNavigationTests` holds the other half: a chord that is not the
    /// shortcut is not forgiven, and with nothing bound none is.
    func testTheShortcutsOwnChordStillLeavesTheWordConvertible() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord(layoutShortcut))

        engine.convertLastWord()

        XCTAssertEqual(typing.performed.count, 1)
        XCTAssertEqual(typing.performed[0].backspaces, 6)
        XCTAssertEqual(typing.performed[0].insert, "привет")
    }

    /// And a word still being typed is untouched by any of this: the buffer is
    /// the caret's own neighbourhood by definition, so the gesture converts it
    /// mid-word whatever happened before it.
    func testAWordStillBeingTypedAfterTheArrowIsStillConverted() {
        let engine = engine()
        tap.type("xxx")
        tap.send(.navigation)          // that word is gone
        tap.type("ghbdtn")             // this one is under the caret

        engine.convertLastWord()

        XCTAssertEqual(typing.performed.count, 1)
        XCTAssertEqual(typing.performed[0].backspaces, 6,
                       "the gesture must still fix the word the caret is inside")
    }
}
