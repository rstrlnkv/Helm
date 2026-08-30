import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **The tap dying is the moment every blind edit the engine is holding stops
/// being checkable — and nothing lets go of them.**
///
/// `tapDied()` is the reverse channel `TheTapSaysWhenMacOSTakesItAwayTests`
/// exists for, and it repairs exactly one thing: the flag the page draws.
/// `tapped` goes false, the state is emitted, the module stops claiming to
/// watch. What it does not do is what `deactivate()` does one screen down —
/// `forgetTheWord()`, which drops the buffer, the remembered word and the undo
/// record together.
///
/// Those three are blind edits: a fixed count of backspaces sent at whatever
/// the caret is in front of *now*, correct only while the caret has not moved.
/// Every guard in this module that keeps them correct is fed by the tap. The
/// remembered word is dropped by `.click`; the undo record is invalidated by
/// every keystroke; the buffer is cleared at every boundary. With the tap gone
/// none of those events will ever arrive again, so all three freeze at the value
/// they had the instant the grant was withdrawn and are trusted **for the life
/// of the process**.
///
/// And the second door is still open while that is true. The gesture is gone
/// with the tap, but the global shortcut is not: `HotkeyManager` registers it
/// through Carbon's `RegisterEventHotKey`, which needs no Accessibility grant at
/// all, and it sends `LayoutCommand.fix` straight into the engine. So the
/// sequence is: macOS revokes the grant, the person carries on typing for ten
/// minutes with Helm blind, presses the shortcut — and six backspaces measured
/// against a word from ten minutes ago land in the middle of a paragraph.
///
/// The app check cannot save any of this: the person never left the app.
///
/// Either repair answers all three tests — `tapDied()` forgetting the word the
/// way `deactivate()` does, or the three doors refusing while `tapped` is false.
/// What is not a repair is the page going honest while the typing does not.
@MainActor
final class TheGrantGoingAwayTakesTheWordWithItTests: XCTestCase {
    private var typing = FakeTyping()
    private var secure = FakeSecure()
    private var tap = FakeTap()
    private var sources = FakeSources()

    /// No `settings:` store on purpose — nothing here is about what was saved,
    /// and an engine with no store cannot reach `UserDefaults` to find out.
    private func engine() -> LayoutEngine {
        typing = FakeTyping(); secure = FakeSecure(); tap = FakeTap(); sources = FakeSources()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: secure)
        engine.activate()
        return engine
    }

    // MARK: - The word that most recently ended

    /// ⌘Tab, ⌘S, the module's own shortcut: every chord ends the word without
    /// converting it, and the word is remembered so the gesture has something to
    /// work on. Then macOS takes the tap away.
    func testAWordRememberedWhenTheGrantWentIsNotTheGesturesToConvert() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.handler?(.chord)
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing has been converted yet")

        tap.macOSTakesItAway()

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            the grant was withdrawn and the remembered word outlived it. Nothing will ever \
            clear it again — no click, no keystroke, no boundary reaches a dead tap — so the \
            Carbon shortcut, which needs no grant, types six backspaces measured against a \
            word from arbitrarily long ago into whatever the caret is in front of now.
            """)
        engine.deactivate()   // drops the didBecomeActive observer this test registered
    }

    /// The positive control for the two tests above and below it: with the tap
    /// alive the very same word *is* the gesture's to convert, so «nothing was
    /// typed» is a refusal the grant caused rather than a sequence that never
    /// reached the typing port at all.
    func testTheSameWordIsStillTheGesturesToConvertWhileTheTapIsAlive() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.handler?(.chord)

        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1,
                       "the harness never reaches a conversion, so the refusals it asserts "
                       + "elsewhere prove nothing")
        XCTAssertEqual(typing.performed.first?.backspaces, 6)
        engine.deactivate()   // drops the didBecomeActive observer this test registered
    }

    // MARK: - The word still being typed

    /// The other half of `convertLastWord`, and the one with no app check of its
    /// own: `buffer.wholeWord` is a word nothing has ended yet. A word half
    /// typed when the tap dies stays half typed in the engine for ever, while
    /// the person finishes it, deletes it, or leaves the field.
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
        engine.deactivate()   // drops the didBecomeActive observer this test registered
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
        engine.deactivate()   // drops the didBecomeActive observer this test registered
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
        engine.deactivate()   // drops the didBecomeActive observer this test registered
    }
}
