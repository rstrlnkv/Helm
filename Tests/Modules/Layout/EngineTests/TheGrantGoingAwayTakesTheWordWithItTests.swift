import HelmTestSupport
import HelmRuntime
import XCTest
@testable import Module_Layout_Engine

/// The tap dying is the moment every blind edit the engine is holding stops
/// being checkable, so the engine lets go of them.
///
/// `tapDied()` is the reverse channel `TheTapSaysWhenMacOSTakesItAwayTests`
/// holds for the flag the page draws. These hold the other half: the buffer,
/// the remembered word and the undo record.
///
/// Those three are blind edits: a fixed count of backspaces sent at whatever
/// the caret is in front of *now*, correct only while the caret has not moved.
/// Every guard in this module that keeps them correct is fed by the tap. The
/// remembered word is dropped by `.click`; the undo record is invalidated by
/// every keystroke; the buffer is cleared at every boundary. With the tap gone
/// none of those events will ever arrive again, so all three would freeze at
/// the value they had when the grant was withdrawn.
///
/// The global shortcut outlives the tap: `HotkeyManager` registers it through
/// Carbon's `RegisterEventHotKey`, which needs no Accessibility grant, and it
/// calls `fix()`. So the person types on for ten minutes with Helm blind,
/// presses the shortcut, and six backspaces measured against a word from ten
/// minutes ago would land in the middle of a paragraph. The app check cannot
/// help: the person never left the app.
@MainActor
final class TheGrantGoingAwayTakesTheWordWithItTests: XCTestCase {
    private var typing = FakeTyping()
    private var secure = FakeSecure()
    private var tap = FakeTap()
    private var sources = FakeSources()

    private func engine() -> LayoutEngine {
        typing = FakeTyping(); secure = FakeSecure(); tap = FakeTap(); sources = FakeSources()
        let store = layoutStore(bound: true)
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: secure, activation: FakeActivation(), settings: store)
        engine.activate()
        return engine
    }

    // MARK: - The word that most recently ended

    /// The module's own shortcut ends the word without converting it, and the
    /// word is remembered so the gesture has something to work on (any other
    /// chord ends it without remembering). Then macOS takes the tap away.
    func testAWordRememberedWhenTheGrantWentIsNotTheGesturesToConvert() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.handler?(.chord(layoutShortcut))
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing has been converted yet")

        tap.macOSTakesItAway()

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            the grant was withdrawn and the remembered word outlived it. Nothing will ever \
            clear it again — no click, no keystroke, no boundary reaches a dead tap — so the \
            Carbon shortcut, which needs no grant, types six backspaces measured against a \
            word from arbitrarily long ago into whatever the caret is in front of now.
            """)
        engine.deactivate()
    }

    /// The positive control for the two tests above and below it: with the tap
    /// alive the very same word *is* the gesture's to convert, so «nothing was
    /// typed» is a refusal the grant caused rather than a sequence that never
    /// reached the typing port at all.
    func testTheSameWordIsStillTheGesturesToConvertWhileTheTapIsAlive() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.handler?(.chord(layoutShortcut))

        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1,
                       "the harness never reaches a conversion, so the refusals it asserts "
                       + "elsewhere prove nothing")
        XCTAssertEqual(typing.performed.first?.backspaces, 6)
        engine.deactivate()
    }

    // MARK: - The word still being typed

    /// The other half of `convertLastWord`, and the one with no app check of its
    /// own: `buffer.wholeWord` is a word nothing has ended yet. Kept after the
    /// tap dies, it would stay half typed in the engine while the person
    /// finishes it, deletes it, or leaves the field.
    func testAWordHalfTypedWhenTheGrantWentIsNotTheGesturesToConvert() {
        let engine = engine()
        tap.type("ghbdtn")      // mid-word: nothing has ended it
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing has been converted yet")

        tap.macOSTakesItAway()

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            the buffer survived the tap that fills it. Every character typed after the grant \
            went is invisible to the engine, so the plan deletes six characters from a field \
            that may hold sixty by now.
            """)
        engine.deactivate()
    }

    // MARK: - The conversion that could still be taken back

    /// `UndoRecord.valid` means «nothing has happened since», and the only thing
    /// that can ever make it false is an event off the tap. Once the tap is
    /// dead the record cannot be falsified, which is not the same as it being
    /// true — it is the module having lost the ability to tell.
    func testAnUndoIsNotStillOfferedAfterTheTapThatWouldFalsifyItDied() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.space()
        XCTAssertEqual(typing.performed.count, 1, "precondition: the word was converted")

        tap.macOSTakesItAway()

        engine.undoLast()
        XCTAssertEqual(typing.performed.count, 1, """
            the undo record outlived the tap that invalidates it. The person kept typing \
            past the conversion with Helm blind; the shortcut then deleted \
            \(typing.performed.last?.backspaces ?? 0) characters wherever the caret had \
            got to and typed the mislayout word back.
            """)
        engine.deactivate()
    }

    /// …and the same undo is still offered while the tap is alive, so the
    /// assertion above is about the grant and not about undo being dead in
    /// general.
    func testTheUndoIsStillOfferedWhileTheTapIsAlive() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.space()
        XCTAssertEqual(typing.performed.count, 1, "precondition: the word was converted")

        engine.undoLast()
        XCTAssertEqual(typing.performed.count, 2, "the harness never reaches an undo")
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn ")
        engine.deactivate()
    }
}
