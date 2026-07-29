import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

// The fakes are per-file on purpose: the ones in LayoutEngineTests are
// file-private, and a shared set would tempt the next person to change one
// suite's world to suit another's.

private final class EdgeTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class EdgeContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { bundle }
}

/// Translates anything: this suite is about lengths and endings, not about
/// which words a dictionary knows.
private struct EdgeTranslation: TranslationPort {
    let table: [String: String]
    func translate(_ word: String, from: String, to: String) -> String? {
        if let known = table[word] { return known }
        return String(repeating: "п", count: word.count)
    }
}

/// Anything Cyrillic is a word; anything typed in Latin is not. That is the
/// shape of every real mislayout.
private struct EdgeSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class EdgeTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void) -> Bool {
        handler = onEvent
        modifiers = onModifier
        return true
    }
    /// One clean press and release of the bound key.
    func tapKey(_ code: Int64, at: TimeInterval = 0) {
        modifiers?(.down(code, at: at, othersHeld: false))
        modifiers?(.up(code, at: at + 0.05))
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
}

private final class EdgeSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) { selected.append(sourceID) }
}

final class LayoutEngineEdgeTests: XCTestCase {
    private var typing = EdgeTyping()
    private var context = EdgeContext()
    private var tap = EdgeTap()
    private var sources = EdgeSources()

    private func engine(triggers: ConversionTriggers = .default,
                        settings: NamespacedStore? = nil,
                        table: [String: String] = [:]) -> LayoutEngine {
        typing = EdgeTyping(); context = EdgeContext(); tap = EdgeTap(); sources = EdgeSources()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: EdgeTranslation(table: table),
                                  spell: EdgeSpell(), secure: context,
                                  triggers: triggers, settings: settings)
        engine.activate()
        return engine
    }

    /// The plan is a count of backspaces sent blind into somebody else's text
    /// field. It may be right or it may be refused, but it must never be
    /// *short*: deleting fewer characters than were typed leaves the head of
    /// the word in place and types the replacement after it.
    ///
    /// The buffer stops at 64 characters and the field does not, so a 70-letter
    /// token converted from a 64-letter buffer eats 65 of 71 characters.
    func testNoPlanDeletesLessThanWasTyped() {
        let engine = engine()
        let typed = TypingBuffer.maxLength + 6
        tap.type(String(repeating: "g", count: typed))
        tap.send(.space)
        if let plan = typing.performed.first {
            XCTAssertGreaterThanOrEqual(
                plan.backspaces, typed + 1,
                "\(typed) letters and a space are in the field; the plan deletes "
                + "\(plan.backspaces) and then types \(plan.insert.count) characters")
        }
        withExtendedLifetime(engine) {}
    }

    /// The promise beside the shortcut is "undo it with the shortcut below, in
    /// the app it happened in". The shortcut cannot be a bare key — the
    /// recorder refuses one — and the tap is head-inserted, so Helm's engine
    /// sees the chord *before* Carbon delivers the hotkey and turns it into
    /// `.chord`. `handle` invalidates the undo on every event it sees, so by
    /// the time `undoLast` runs the record it needs is already dead.
    ///
    /// The fix is not to stop invalidating on caret movement — ⌘→ really does
    /// move the caret. It is that the one chord which *is* the undo shortcut
    /// must not destroy its own precondition. Which bare keys may spend that
    /// forgiveness is `UndoAfterNavigationTests`.
    func testTheUndoShortcutCanUndo() {
        let engine = engine(table: ["ghbdtn": "привет"])
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, 1, "precondition: the word was converted")

        tap.send(.chord)        // the chord the user just pressed, seen by the tap first
        engine.undoLast()       // …and then delivered to Helm by Carbon
        XCTAssertEqual(typing.performed.count, 2, "the undo shortcut did nothing")
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn ",
                       "undo puts back what was replaced, ending and all")
    }

    /// The stored default and the documented default are the same default.
    ///
    /// `ConversionTriggers.default` says Return is off, and says why at length:
    /// in a chat Return sends the message and empties the field, so the
    /// backspaces delete nothing, the replacement is typed into an empty box
    /// and the newline sends it — the other person gets the mistyped word and
    /// then a second message correcting it. Every place that reads the setting
    /// out of the store asks for `default: true`, so on a machine where nobody
    /// has touched the switch, Return converts.
    func testTheStoredDefaultsMatchTheDocumentedOnes() async throws {
        let store = NamespacedStore(namespace: "layout", backing: InMemoryKeyValueStore())
        let engine = engine(settings: store, table: ["ghbdtn": "привет"])
        // Nothing has been written to the store: this is a fresh install
        // reading its own defaults.
        _ = try await engine.transport.send(EngineCommand(name: "settingsChanged"))

        tap.type("ghbdtn")
        tap.send(.newline)
        XCTAssertTrue(typing.performed.isEmpty,
                      "Return converted on a store nobody has written to")

        // …and the two that are documented as on stay on, so the answer is not
        // "switch everything off". Counted as increments, so these two stand on
        // their own whatever Return did above.
        var seen = typing.performed.count
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, seen + 1, "a space still confirms by default")
        seen = typing.performed.count
        tap.type("ghbdtn")
        tap.send(.punctuation("."))
        XCTAssertEqual(typing.performed.count, seen + 1, "punctuation still confirms by default")
    }

    /// A word abandoned by clicking somewhere else is not the word under the
    /// caret any more, and the hotkey must not go looking for it.
    ///
    /// The engine remembers the last completed word so its own shortcut — a
    /// chord, which ends the word before Carbon delivers it — has something to
    /// work on. But *every* boundary arms that memory, including the click,
    /// which the module's own rules call "the person went somewhere else".
    /// Type six letters, click into another field, press convert: six
    /// backspaces and a Russian word land wherever the caret now is. Nothing
    /// expires it either — the click could have been an hour ago.
    func testAWordLeftBehindByAClickIsNotTheHotkeysToConvert() {
        let engine = engine(table: ["ghbdtn": "привет"])
        tap.type("ghbdtn")
        tap.send(.click)            // the caret is now somewhere else entirely
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty,
                      "the hotkey retyped a word the user had already left")
    }

    /// …and the ordinary path still works afterwards: the word typed *after*
    /// the click is the one the hotkey converts.
    func testTheWordTypedAfterAClickIsStillConvertible() {
        let engine = engine(table: ["ghbdtn": "привет"])
        tap.type("abc")
        tap.send(.click)
        tap.type("ghbdtn")
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.first?.insert, "привет")
        XCTAssertEqual(typing.performed.first?.backspaces, 6)
    }

    /// Switched off is switched off, and the word goes with it.
    ///
    /// `deactivate` clears the buffer and the undo record on purpose — the
    /// module's own note is that a tap sees passwords typed into fields an app
    /// forgot to mark secure, and the only safe place for them is somewhere
    /// already gone. The remembered last word is the third place a word lives
    /// and the one that is not cleared, so it outlives the module that was
    /// turned off.
    func testATurnedOffModuleTypesNothingAndRemembersNothing() {
        let engine = engine(table: ["ghbdtn": "привет"])
        tap.type("ghbdtn")
        // A chord, not an arrow: a caret move now forgets the word by itself, so
        // arranging this with one would prove nothing about `deactivate`.
        tap.send(.chord)        // ends the word without converting; it is remembered
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")
        engine.deactivate()
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, "a module that is off typed into an app")
        let seen = typing.performed.count
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, seen,
                       "and it must not undo into an app either")
    }

    /// A trigger the user switched off stays off across a settings reload —
    /// the store is the source of truth once it has been written to.
    func testAStoredChoiceSurvivesTheReload() async throws {
        let backing = InMemoryKeyValueStore()
        let store = NamespacedStore(namespace: "layout", backing: backing)
        store.set(false, for: "onSpace")
        let engine = engine(settings: store, table: ["ghbdtn": "привет"])
        _ = try await engine.transport.send(EngineCommand(name: "settingsChanged"))
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertTrue(typing.performed.isEmpty, "the user switched the space off")
    }
}

/// The engine has to read its own settings when it starts.
///
/// It did not. `reloadSettings()` ran only when the transport announced a
/// change, so on every launch the engine kept the values its initialiser
/// happened to hold — and the tap key has no initialiser parameter at all, so
/// it stayed `.off`. The gesture therefore worked only in a session where
/// somebody had opened the Keyboard page and changed something, and was gone
/// again after the next restart. Nothing was written to the log, because `.off`
/// refuses before there is anything to refuse.
///
/// The test that was supposed to cover this sent `settingsChanged` itself
/// first, which is the one thing a fresh launch does not do.
final class SettingsAtStartTests: XCTestCase {

    private final class CountingTap: KeyTapPort, @unchecked Sendable {
        var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
        func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                   onModifier: @escaping @Sendable (ModifierTap.Input) -> Void) -> Bool {
            modifiers = onModifier
            return true
        }
        func stop() {}
        func tapKey(_ code: Int64) {
            modifiers?(.down(code, at: 0, othersHeld: false))
            modifiers?(.up(code, at: 0.05))
        }
    }

    func testTheBoundKeyWorksOnAFreshLaunchWithNothingStored() {
        let tap = CountingTap()
        let sources = EdgeSources()
        let engine = LayoutEngine(tap: tap, typing: EdgeTyping(), sources: sources,
                                  translation: EdgeTranslation(table: ["ghbdtn": "привет"]),
                                  spell: EdgeSpell(), secure: EdgeContext(),
                                  settings: NamespacedStore(namespace: "layout",
                                                            backing: InMemoryKeyValueStore()))
        engine.activate()
        // No `settingsChanged`: this is the launch, not a visit to the page.

        // The documented default is the right Command key. Tapping it has to
        // reach the engine — which it can only do if the key was ever read.
        XCTAssertNotEqual(engine.boundTapKey, .off,
                          "the engine never read its own settings at start")
        tap.tapKey(TapKey.rightCommand.keyCode!)
        withExtendedLifetime(engine) {}
    }
}
