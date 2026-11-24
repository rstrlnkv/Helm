import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

/// The third place a word lives.
///
/// `buffer` is the word being typed and `undo` is the conversion that can still
/// be taken back; both are cleared everywhere they must be. `lastCompleted` is
/// the word that most recently *ended*, kept so the gesture — which is itself a
/// chord, and therefore ends the word before Carbon delivers it — has something
/// to work on.
///
/// It is state accumulated from the event stream, so each case asks which
/// event clears it: a correction that replaced the word, a selection edit that
/// moved the caret, a secure field that refused it, the app going away.
///
/// Each guards the same harm: the gesture sending a fixed number of backspaces
/// at whatever has the keyboard now, counted from a word that is no longer
/// there.
final class LayoutEngineStaleWordTests: XCTestCase {
    private var typing = FakeTyping()
    private var context = FakeSecure()
    private var tap = FakeTap()
    private var sources = FakeSources(follows: false)
    private var selection = FakeSelection()

    /// A store with that binding in it, because these suites use a chord as the
    /// boundary that remembers.
    /// Every setting this suite varies goes in the store, not only in the
    /// initialiser: `activate()` calls `reloadSettings()`, which overwrites the
    /// initialiser's values with the store's. The test speaks to the engine the
    /// way the page does.
    /// Architecture/ModulePattern.md § The stream and the store.
    private static func boundStore(fixCapitals: Bool = false) -> NamespacedStore {
        let store = layoutStore(bound: true)
        store.set(fixCapitals, for: LayoutKey.fixCapitals)
        return store
    }

    private func engine(                        fixCapitals: Bool = false) -> LayoutEngine {
        typing = FakeTyping(); context = FakeSecure()
        tap = FakeTap(); sources = FakeSources(follows: false); selection = FakeSelection()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: FakeTranslation(sameLength: true), spell: FakeSpell(valid: ["Hello"], cyrillic: true),
                                  secure: context, activation: FakeActivation(), selection: selection,
 fixCapitals: fixCapitals,
                                  settings: Self.boundStore(fixCapitals: fixCapitals))
        engine.activate()
        return engine
    }

    // MARK: - A word that was replaced by something else

    /// A held capital was corrected, so the field holds `Hello` and the engine
    /// still remembers `HEllo`. Two edits to one word is the thing this order
    /// of operations exists to prevent.
    func testACorrectedCapitalIsNotStillThereToConvert() {
        let engine = engine(fixCapitals: true)
        tap.type("HEllo")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, 1, "precondition: the capital was corrected")
        XCTAssertEqual(typing.performed[0].insert, "Hello ")

        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1,
                       "the gesture converted the word the correction had already replaced")
    }

    /// A selection was converted, which typed into the field and moved the
    /// caret. `convertSelection` clears the buffer and the undo record for that
    /// reason, and the remembered word with them.
    func testConvertingASelectionLeavesNoWordBehind() async throws {
        let engine = engine()
        tap.type("vjq")
        // A chord, not an arrow: a caret move forgets the word on its own, and
        // the subject here is what the selection edit leaves behind.
        tap.send(.chord(layoutShortcut))          // ends the word without converting; it is remembered
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")

        selection.text = "ghbdtn"
        engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Notes")
        XCTAssertEqual(selection.replaced.count, 1, "precondition: the selection was replaced")

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "the caret is wherever the selection edit left it; the gesture sent "
                      + "backspaces for a word typed before it")
    }

    // MARK: - A word the module refused to touch

    /// The password case, and the reason the module clears all three places
    /// whenever secure input turns on.
    ///
    /// `isSecureInput` is false here — that is the point. The cheap check that
    /// runs on every key cannot see an application's own password field, so
    /// every character reaches the buffer and the word is remembered when the
    /// space ends it. Only then does `convert` make the expensive call, see the
    /// password field and refuse. If the word stayed, the person tabbing into an
    /// ordinary field and tapping the key would get their password converted
    /// into it.
    func testAWordRefusedByAPasswordFieldIsNotRemembered() {
        let engine = engine()
        context.passwordField = true
        tap.type("swordfish")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "precondition: the password field refused")

        // Out of the password field, same app, same session.
        context.passwordField = false
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "the password was still in the engine and the gesture typed it back")
    }

    /// A blocked app is refused before the dictionary is consulted — and the
    /// word it refused stays. `AppScope` says a terminal is not a place to
    /// rewrite text; that has to mean the text does not leave with the module
    /// either.
    func testAWordRefusedByABlockedAppIsNotCarriedOut() {
        let engine = engine()
        context.bundle = "com.apple.Terminal"
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "precondition: the terminal was refused")

        context.bundle = "com.apple.Notes"
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "a word from a blocked app was retyped into a different one")
    }

    // MARK: - A word in an app that is no longer in front

    /// ⌘Tab is the case the click test does not cover.
    ///
    /// The engine refuses to convert a word abandoned by a *click*, because the
    /// caret is somewhere else. Switching apps by keyboard is the same event to
    /// the person and a different one to the tap: every chord arrives as
    /// `.chord`, which ends the word and remembers it. No event
    /// tells the engine the app changed.
    ///
    /// `UndoRecord` carries the bundle id and refuses to fire anywhere else: a
    /// blind edit is only correct in the app it was measured in. The remembered
    /// word is the same kind of blind edit.
    func testAWordLeftBehindInAnotherAppIsNotTheGesturesToConvert() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord(layoutShortcut))               // ⌘Tab, as the tap reports it
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")

        context.bundle = "com.apple.Mail"
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "six backspaces and a Russian word landed in the app the person "
                      + "switched to")
    }

    /// A chord that is not the bound shortcut takes the word with it.
    ///
    /// Type `ghbdtn`, ⌘V a link, tap the key: without this,
    /// `ghbdtnhttps://helm.app` becomes `ghbdtnhttps://heпривет`. The
    /// forgiveness `.chord` carries is for one chord, the recorded hotkey, whose
    /// keys the head-inserted tap sees before Carbon dispatches the action. ⌘V
    /// pastes and ⌥V types `√`; both change the text in front of the caret.
    func testAChordThatIsNotTheShortcutIsNotAWordTheGestureMayConvert() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord(layoutShortcut &+ 1))     // ⌘V, or anything that is not the binding

        engine.convertLastWord()

        XCTAssertTrue(typing.performed.isEmpty, """
            the gesture converted a word that a chord had ended. That chord may have \
            pasted, typed a character or moved the caret — the module cannot know — and \
            the backspaces are counted against text that was in front of the caret before \
            it happened.
            """)
    }

    /// …and the same word in the app it was typed in is still the gesture's to
    /// convert, so the answer above is not "refuse everything".
    func testTheWordIsStillConvertibleInTheAppItWasTypedIn() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord(layoutShortcut))
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1)
        XCTAssertEqual(typing.performed[0].backspaces, 6)
    }

    // MARK: - A word the buffer could not hold

    /// The overflow refusal is right and leaves the wrong word standing.
    ///
    /// A token longer than the buffer is reported as *nothing*, on purpose: the
    /// buffer holds a prefix of it and a plan built from a prefix deletes fewer
    /// characters than were typed. But "nothing finished" is not "nothing
    /// happened": the previous remembered word must not survive it, or the
    /// gesture converts a word from before a seventy-character token with the
    /// caret seventy characters further on.
    func testATokenTooLongToHoldDoesNotLeaveTheWordBeforeItStanding() {
        let engine = engine()
        tap.type("ghbdtn")
        // A chord, not an arrow, for the same reason: the subject is the token
        // the buffer refused, not the boundary that set the word up.
        tap.send(.chord(layoutShortcut))                // ends the word without converting; it is remembered
        tap.type(String(repeating: "g", count: TypingBuffer.maxLength + 6))
        tap.send(.space)                // too long to report — and it is not reported
        XCTAssertTrue(typing.performed.isEmpty, "precondition: the long token was refused")

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "the gesture reached back past a token it had refused to read and "
                      + "sent six backspaces \(TypingBuffer.maxLength + 7) characters "
                      + "downstream of the word it measured")
    }

    // MARK: - The selection, which is text Helm has never seen

    /// The selection path edits text the module did not watch being typed, in
    /// an app it did not choose. The two refusals that make that acceptable are
    /// the same two the word path applies, held here at the engine level.
    func testASelectionIsNotConvertedInABlockedApp() async throws {
        let engine = engine()
        context.bundle = "com.apple.Terminal"
        selection.text = "ghbdtn"
        engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Terminal")
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    func testASelectionIsNotConvertedIntoASecureField() async throws {
        let engine = engine()
        context.passwordField = true
        selection.text = "ghbdtn"
        engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Notes")
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    /// Whitespace is not a selection to convert: replacing it with itself, or
    /// with anything, is an edit that clears the app's undo stack for nothing.
    func testAWhitespaceSelectionIsLeftAlone() async throws {
        let engine = engine()
        for blank in ["", "   ", "\n", "\t\t", " \n "] {
            selection.text = blank
            engine.convertSelection(selected: blank, readIn: "com.apple.Notes")
            XCTAssertTrue(selection.replaced.isEmpty, "selection was \(blank.debugDescription)")
        }
    }

    // MARK: - A module that is off

    /// `deactivate` clears the buffer, the undo record and the remembered word,
    /// and the word path types nothing afterwards. The selection path makes the
    /// same promise: `convertSelection` asks whether the module is running.
    func testATurnedOffModuleDoesNotConvertASelection() async throws {
        let engine = engine()
        selection.text = "ghbdtn"
        engine.deactivate()
        engine.convertSelection(selected: "ghbdtn", readIn: "com.apple.Notes")
        XCTAssertTrue(selection.replaced.isEmpty,
                      "a module that is switched off replaced text in another app")
    }
}
