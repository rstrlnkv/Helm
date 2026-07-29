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
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void) -> Bool {
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

    private func engine(autoReplace: [AutoReplace.Entry] = [],
                        fixCapitals: Bool = false) -> LayoutEngine {
        typing = StaleTyping(); context = StaleContext()
        tap = StaleTap(); sources = StaleSources(); selection = StaleSelection()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: StaleTranslation(), spell: StaleSpell(),
                                  secure: context, selection: selection,
                                  autoReplace: autoReplace, fixCapitals: fixCapitals)
        engine.activate()
        return engine
    }

    // MARK: - A word that was replaced by something else

    /// An abbreviation expanded, so the field no longer holds the word the
    /// buffer reported — it holds the expansion. The engine remembers the
    /// abbreviation anyway, and the gesture then converts it: `brb` was three
    /// characters, `be right back` is thirteen, and four backspaces land in the
    /// middle of the sentence that replaced it.
    ///
    /// The module's own rule is that a word which expanded must never also be
    /// converted. `handle` honours it in the same breath — and then leaves the
    /// word where a keystroke later can pick it up.
    func testAWordThatExpandedIsNotStillThereToConvert() {
        let engine = engine(autoReplace: [AutoReplace.Entry(from: "brb", to: "be right back")])
        tap.type("brb")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, 1, "precondition: the abbreviation expanded")
        XCTAssertEqual(typing.performed[0].insert, "be right back ")

        // The field now reads "be right back ". Nothing in it is `brb`.
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1,
                       "the gesture typed a conversion of a word the expansion had already "
                       + "replaced")
    }

    /// The same, one door down: a held capital was corrected, so the field
    /// holds `Hello` and the engine still remembers `HEllo`. Two edits to one
    /// word is the thing this order of operations exists to prevent.
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
        tap.send(.chord)          // ends the word without converting; it is remembered
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")

        selection.text = "ghbdtn"
        _ = try await engine.transport.send(EngineCommand(name: "convertSelection"))
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
        tap.send(.chord)               // ⌘Tab, as the tap reports it
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")

        context.bundle = "com.apple.Mail"
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "six backspaces and a Russian word landed in the app the person "
                      + "switched to")
    }

    /// …and the same word in the app it was typed in is still the gesture's to
    /// convert, so the answer above is not "refuse everything".
    func testTheWordIsStillConvertibleInTheAppItWasTypedIn() {
        let engine = engine()
        tap.type("ghbdtn")
        tap.send(.chord)
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
        tap.send(.chord)                // ends the word without converting; it is remembered
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
        _ = try await engine.transport.send(EngineCommand(name: "convertSelection"))
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    func testASelectionIsNotConvertedIntoASecureField() async throws {
        let engine = engine()
        context.passwordField = true
        selection.text = "ghbdtn"
        _ = try await engine.transport.send(EngineCommand(name: "convertSelection"))
        XCTAssertTrue(selection.replaced.isEmpty)
    }

    /// Whitespace is not a selection to convert: replacing it with itself, or
    /// with anything, is an edit that clears the app's undo stack for nothing.
    func testAWhitespaceSelectionIsLeftAlone() async throws {
        let engine = engine()
        for blank in ["", "   ", "\n", "\t\t", " \n "] {
            selection.text = blank
            _ = try await engine.transport.send(EngineCommand(name: "convertSelection"))
            XCTAssertTrue(selection.replaced.isEmpty, "selection was \(blank.debugDescription)")
        }
    }

    /// An app that refuses to say what is selected is an app with no selection,
    /// and the module has nothing to do rather than something to guess.
    func testAnAppThatWillNotSayWhatIsSelectedIsLeftAlone() async throws {
        let engine = engine()
        selection.text = nil
        _ = try await engine.transport.send(EngineCommand(name: "convertSelection"))
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
        _ = try await engine.transport.send(EngineCommand(name: "convertSelection"))
        XCTAssertTrue(selection.replaced.isEmpty,
                      "a module that is switched off replaced text in another app")
    }
}
