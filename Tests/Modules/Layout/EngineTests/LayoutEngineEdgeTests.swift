import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

final class LayoutEngineEdgeTests: XCTestCase {
    private var typing = FakeTyping()
    private var context = FakeSecure()
    private var tap = FakeTap()
    private var sources = StuckSources()

    private func engine(                        settings: NamespacedStore? = nil,
                        table: [String: String] = [:]) -> LayoutEngine {
        typing = FakeTyping(); context = FakeSecure(); tap = FakeTap(); sources = StuckSources()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: SameLengthTranslation(table: table),
                                  spell: CyrillicSpell(), secure: context, activation: FakeActivation(),
                                  settings: settings ?? layoutStore(bound: true))
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

        tap.send(.chord(layoutShortcut))        // the chord the user just pressed, seen by the tap first
        engine.undoLast()       // …and then delivered to Helm by Carbon
        XCTAssertEqual(typing.performed.count, 2, "the undo shortcut did nothing")
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn ",
                       "undo puts back what was replaced, ending and all")
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
        tap.send(.chord(layoutShortcut))        // ends the word without converting; it is remembered
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing was converted")
        engine.deactivate()
        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, "a module that is off typed into an app")
        let seen = typing.performed.count
        engine.undoLast()
        XCTAssertEqual(typing.performed.count, seen,
                       "and it must not undo into an app either")
    }
}

/// The engine has to read its own settings when it starts.
///
/// `reloadSettings()` runs in `activate()`, not only when a change is announced:
/// otherwise a launch keeps the values the initialiser holds, and the tap key,
/// which has no initialiser parameter, stays `.off`; the gesture then refuses
/// silently, before there is anything to log. A test that sends `settingsChanged`
/// itself first does the one thing a fresh launch does not.
final class SettingsAtStartTests: XCTestCase {

    private final class CountingTap: KeyTapPort, @unchecked Sendable {
        var modifiers: (@Sendable (ModifierTap.Input) -> Void)?
        func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
                   onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
                   died: @escaping @Sendable () -> Void) -> Bool {
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
        let sources = StuckSources()
        let engine = LayoutEngine(tap: tap, typing: FakeTyping(), sources: sources,
                                  translation: SameLengthTranslation(table: ["ghbdtn": "привет"]),
                                  spell: CyrillicSpell(), secure: FakeSecure(), activation: FakeActivation(),
                                  settings: layoutStore())
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
