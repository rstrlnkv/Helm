import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

// Fakes are per-file in this suite, by the convention the others follow.

private final class ArrowTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class ArrowContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { bundle }
}

private struct ArrowTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        word == "ghbdtn" ? "привет" : nil
    }
}

private struct ArrowSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class ArrowTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void) -> Bool {
        handler = onEvent
        return true
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
}

private final class ArrowSources: LayoutSourcePort, @unchecked Sendable {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

/// The other half of the arrow-key defect.
///
/// `UndoAfterNavigationTests` pinned the undo half: type `ghbdtn `, watch it
/// convert, press Left Arrow, tap the bound modifier — the undo used to fire and
/// send backspaces at a caret it no longer knew. `undo?.invalidate()` on
/// `.navigation` closed it.
///
/// The gesture has a second outcome and it reads the same blind edit off a
/// different field. With no undo record to spend, `fix()` falls through to
/// `convertLastWord()`, which reaches for `lastCompleted` — the word that most
/// recently *ended*. `handle()` clears that field for `.click` and
/// `.focusChange` and sets it for everything else, so a bare arrow, Home, End,
/// Tab or Escape *stores* the word it just ended instead of dropping it.
///
/// Both fields carry the same promise. `RememberedWord`'s own doc says
/// converting it "is only correct while the caret is still where the word left
/// it — which is the same reasoning `UndoRecord` is built on, and the same check
/// it makes"; `TypingBuffer.Event.navigation`'s says the caret moved and "what
/// came before is no longer adjacent to what comes next". The check is the one
/// thing that is not the same.
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
    private var typing = ArrowTyping()
    private var context = ArrowContext()
    private var tap = ArrowTap()

    private func engine() -> LayoutEngine {
        typing = ArrowTyping(); context = ArrowContext(); tap = ArrowTap()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: ArrowSources(),
                                  translation: ArrowTranslation(), spell: ArrowSpell(),
                                  secure: context)
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

    /// How narrow the window is, written down so nobody mistakes it for a
    /// reason not to close it.
    ///
    /// `handle()` overwrites the remembered word on *every* event that is not a
    /// click or a focus change, and the overwrite is `finished.map { … }` — so
    /// any second event, having nothing in the buffer to finish, writes nil and
    /// clears it by accident. The word is therefore only exposed while the
    /// caret move is the *most recent* thing that happened, which is exactly the
    /// shape of the gesture: press ↑ or Home or Escape, then tap the key. A
    /// second arrow, or one more character, hides it again.
    ///
    /// This test asserts the accident, not the behaviour, and exists so that a
    /// fix which merely reorders `handle()` cannot be mistaken for one that
    /// clears the field.
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
    /// A chord is the one boundary that is *not* proof the caret moved — the
    /// gesture's own keys reach the tap before Carbon dispatches them — so a
    /// word ended by a chord is still the gesture's to convert.
    func testAWordEndedByAChordIsStillConverted() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord)

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
