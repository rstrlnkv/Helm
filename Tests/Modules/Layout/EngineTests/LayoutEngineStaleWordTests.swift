import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

// The fakes are per-file, as in the other engine suites: a shared set tempts
// the next person to change one suite's world to suit another's.

private final class StaleTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

/// The two halves of the secure check are separate on purpose, and the gap
/// between them is where this suite lives. `isSecureInput` is the cheap syscall
/// asked on every key; it only knows about *system-wide* secure input.
/// `isSecure` is the accessibility round trip that also recognises a password
/// field by its role — an Electron login form, a web field the browser did not
/// escalate for. A password typed into one of those reaches the buffer.
private final class StaleContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    var systemWideSecure = false
    var passwordField = false
    func isSecureInput() -> Bool { systemWideSecure }
    func isSecure() -> Bool { systemWideSecure || passwordField }
    func frontmostBundleID() -> String { bundle }
}

/// Translates anything Latin into Cyrillic of the same length. This suite is
/// about which word the engine reaches for, not about which words a dictionary
/// knows.
private struct StaleTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        guard !word.isEmpty else { return nil }
        return String(repeating: "п", count: word.count)
    }
}

private struct StaleSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class StaleTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        handler = onEvent
        modifiers = onModifier
        return true
    }
    func stop() { handler = nil; modifiers = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
}

private final class StaleSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) { selected.append(sourceID) }
}

private final class StaleSelection: SelectionPort, @unchecked Sendable {
    var text: String?
    var replaced: [String] = []
    func selectedText() -> String? { text }
    func selectedTextWithoutClipboard() -> String? { text }
    func replaceSelection(with text: String) -> Bool { replaced.append(text); return true }
}

/// The third place a word lives.
///
/// `buffer` is the word being typed and `undo` is the conversion that can still
/// be taken back; both are cleared everywhere they must be. `lastCompleted` is
/// the word that most recently *ended*, kept so the gesture — which is itself a
/// chord, and therefore ends the word before Carbon delivers it — has something
/// to work on.
///
/// It is state accumulated from the event stream, and the question the module's
/// own architecture note asks of such state is: which event clears it, and what
/// happens the one time that event never comes. `perform(_:)` clears it and
/// `.click` clears it. Nothing else does — not the expansion that replaced the
/// word in the field, not the selection edit that moved the caret, not the
/// secure field that refused it, and not the app going away.
///
/// Every case below ends in the same harm: the gesture sends a fixed number of
/// backspaces at whatever has the keyboard now, counted from a word that is no
/// longer there.
final class LayoutEngineStaleWordTests: XCTestCase {
    private var typing = StaleTyping()
    private var context = StaleContext()
    private var tap = StaleTap()
    private var sources = StaleSources()
    private var selection = StaleSelection()

    /// The chord bound as «fix». Only the recorded one ends a word and leaves
    /// it remembered: every other chord may have changed the text in front of
    /// the caret — ⌘V pastes, ⌥V types `√` — so the word before it is dropped.
    private static let shortcut: UInt16 = 9

    /// A store with that binding in it, because these suites use a chord as the
    /// boundary that remembers.
    /// **Every setting this suite varies goes in the store, not only in the
    /// initialiser.** `activate()` calls `reloadSettings()`, which overwrites
    /// the initialiser's values with the store's — so once a store exists,
    /// passing `fixCapitals: true` to the init and nothing to the store leaves
    /// the flag off. That is the engine reading its own settings at launch,
    /// which is deliberate (ARCHITECTURE.md § Layout switching); the test has
    /// to speak to it the way the page does.
    private static func boundStore(fixCapitals: Bool = false) -> NamespacedStore {
        let store = NamespacedStore(namespace: LayoutEngine.moduleID,
                                    backing: InMemoryKeyValueStore())
        store.set(Int(shortcut), for: "\(LayoutHotkey.storePrefix)KeyCode")
        store.set(fixCapitals, for: LayoutKey.fixCapitals)
        return store
    }

    private func engine(                        fixCapitals: Bool = false) -> LayoutEngine {
        typing = StaleTyping(); context = StaleContext()
        tap = StaleTap(); sources = StaleSources(); selection = StaleSelection()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: StaleTranslation(), spell: StaleSpell(),
                                  secure: context, selection: selection,
 fixCapitals: fixCapitals,
                                  settings: Self.boundStore(fixCapitals: fixCapitals))
        engine.activate()
        return engine
    }

    // MARK: - A word that was replaced by something else

    /// A held capital was corrected, so the field holds `Hello` and the engine
    /// still remembers `HEllo`. Two edits to one word is the thing this order
    /// of operations exists to prevent.
    ///
    /// It had a twin over abbreviations — `brb` → `be right back`, where four
    /// backspaces landed in the middle of the sentence that replaced it. That
    /// feature is gone; the rule it shared with this one is not, and this is
    /// now the only test holding it.
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
    /// caret. `transform` clears the buffer and the undo record for exactly
    /// that reason and forgets the third one.
    func testConvertingASelectionLeavesNoWordBehind() async throws {
        let engine = engine()
        tap.type("vjq")
        // A chord, not an arrow: a caret move now forgets the word on its own,
        // and the subject here is what the selection edit leaves behind.
        tap.send(.chord(Self.shortcut))          // ends the word without converting; it is remembered
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")

        selection.text = "ghbdtn"
        engine.convertSelection()
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
    /// password field and refuse. It clears the buffer and leaves the word.
    ///
    /// Then the person tabs into an ordinary field and taps the key they
    /// bound: Helm types a conversion of their password into it.
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
    /// `.chord`, which ends the word and remembers it. The real tap never emits
    /// `.focusChange` at all — grep the sources — so nothing tells the engine
    /// the app changed.
    ///
    /// `UndoRecord` already carries the bundle id and refuses to fire anywhere
    /// else, on exactly this reasoning: a blind edit is only correct in the app
    /// it was measured in. The remembered word is the same kind of blind edit
    /// and carries no app at all.
    func testAWordLeftBehindInAnotherAppIsNotTheGesturesToConvert() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord(Self.shortcut))               // ⌘Tab, as the tap reports it
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")

        context.bundle = "com.apple.Mail"
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "six backspaces and a Russian word landed in the app the person "
                      + "switched to")
    }

    /// **A chord that is not the bound shortcut takes the word with it.**
    ///
    /// Measured before the repair, driving a field the plan is applied to: type
    /// `ghbdtn`, press ⌘V so the app pastes a link, tap the key —
    /// `ghbdtnhttps://helm.app` became `ghbdtnhttps://heпривет`. Six backspaces
    /// counted against a word that was six characters upstream of where the
    /// caret had ended up, and the mislayout left standing.
    ///
    /// The forgiveness `.chord` carried existed for one chord — the recorded
    /// hotkey, whose keys the head-inserted tap sees before Carbon dispatches
    /// the action — and every chord was spending it. ⌘V pastes and ⌥V types
    /// `√`; both change the text in front of the caret, and the remembered word
    /// is a blind edit measured against the text that was there before.
    func testAChordThatIsNotTheShortcutIsNotAWordTheGestureMayConvert() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord(Self.shortcut &+ 1))     // ⌘V, or anything that is not the binding

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
        tap.send(.chord(Self.shortcut))
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
    /// happened" — the engine only overwrites the remembered word when a word
    /// finishes, so the refusal leaves the previous one in place. The gesture
    /// then converts a word from before a seventy-character token, with the
    /// caret seventy characters further on.
    func testATokenTooLongToHoldDoesNotLeaveTheWordBeforeItStanding() {
        let engine = engine()
        tap.type("ghbdtn")
        // A chord, not an arrow, for the same reason: the subject is the token
        // the buffer refused, not the boundary that set the word up.
        tap.send(.chord(Self.shortcut))                // ends the word without converting; it is remembered
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
    /// the same two the word path applies, and neither had a test at the engine
    /// level.
    func testASelectionIsNotConvertedInABlockedApp() async throws {
        let engine = engine()
        context.bundle = "com.apple.Terminal"
        selection.text = "ghbdtn"
        engine.convertSelection()
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    func testASelectionIsNotConvertedIntoASecureField() async throws {
        let engine = engine()
        context.passwordField = true
        selection.text = "ghbdtn"
        engine.convertSelection()
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    /// Whitespace is not a selection to convert: replacing it with itself, or
    /// with anything, is an edit that clears the app's undo stack for nothing.
    func testAWhitespaceSelectionIsLeftAlone() async throws {
        let engine = engine()
        for blank in ["", "   ", "\n", "\t\t", " \n "] {
            selection.text = blank
            engine.convertSelection()
            XCTAssertTrue(selection.replaced.isEmpty, "selection was \(blank.debugDescription)")
        }
    }

    /// An app that refuses to say what is selected is an app with no selection,
    /// and the module has nothing to do rather than something to guess.
    func testAnAppThatWillNotSayWhatIsSelectedIsLeftAlone() async throws {
        let engine = engine()
        selection.text = nil
        engine.convertSelection()
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    // MARK: - A module that is off

    /// `deactivate` clears the buffer, the undo record and the remembered word
    /// on purpose, and the existing suite pins that the word path types nothing
    /// afterwards. The selection path is the same promise and has no guard at
    /// all: `transform` never asks whether the module is running.
    func testATurnedOffModuleDoesNotConvertASelection() async throws {
        let engine = engine()
        selection.text = "ghbdtn"
        engine.deactivate()
        engine.convertSelection()
        XCTAssertTrue(selection.replaced.isEmpty,
                      "a module that is switched off replaced text in another app")
    }
}
