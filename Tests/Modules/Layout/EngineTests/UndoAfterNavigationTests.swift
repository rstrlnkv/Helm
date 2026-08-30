import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

// Fakes are per-file in this suite by the same convention the others follow.

private final class NavTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class NavContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { bundle }
}

private struct NavTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        word == "ghbdtn" ? "привет" : nil
    }
}

private struct NavSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class NavTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        handler = onEvent
        return true
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
    func send(_ event: TypingBuffer.Event) { handler?(event) }
}

private final class NavSources: LayoutSourcePort, @unchecked Sendable {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

/// Which keys are allowed to spend the undo's one forgiveness.
///
/// An undo is a blind edit: so many backspaces, then a replacement, at
/// whatever the caret happens to be. `UndoRecord` therefore dies on anything
/// that moved the caret — with one exception, which is not a convenience. The
/// convert/undo shortcut is itself a chord, the head-inserted tap reports its
/// keys *before* Carbon dispatches the action, and a chord treated as "the
/// caret moved" would mean the shortcut destroying its own precondition. So
/// one chord is forgiven and a second is not.
///
/// The budget was being spent by the wrong keys. `SystemPorts` reported both
/// the shortcut's chord and a plain Left Arrow, Home, End, Tab or Escape as
/// the same `.navigation`, so an ordinary caret move was forgiven exactly like
/// the shortcut — and with the default gesture there is nothing to spend the
/// rest of the budget afterwards, because a solo-modifier tap goes through
/// `deliverModifier` and never reaches `handle()`.
///
/// The sequence that cost somebody their text: type `ghbdtn ` → converted to
/// `привет ` → press Left Arrow once → tap the bound modifier → `canUndo` was
/// still true → backspaces and a retype at the new caret, in the middle of the
/// sentence, and the action the person actually wanted was eaten.
final class UndoAfterNavigationTests: XCTestCase {
    private var typing = NavTyping()
    private var context = NavContext()
    private var tap = NavTap()

    private func engine() -> LayoutEngine {
        typing = NavTyping(); context = NavContext(); tap = NavTap()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: NavSources(),
                                  translation: NavTranslation(), spell: NavSpell(),
                                  secure: context)
        engine.activate()
        return engine
    }

    /// Converts a word and leaves an undo record behind it.
    private func converted(_: LayoutEngine) {
        tap.type("ghbdtn")
        tap.send(.space)
        XCTAssertEqual(typing.performed.count, 1, "precondition: the word was converted")
    }

    // MARK: - A bare navigation key

    func testOneArrowKeyEndsTheChanceToUndo() {
        let engine = engine()
        converted(engine)

        tap.send(.navigation)   // Left Arrow, and nothing else
        engine.undoLast()

        XCTAssertEqual(typing.performed.count, 1,
                       "the undo typed backspaces at a caret it no longer knows")
    }

    /// The same key after the shortcut's own chord has already been forgiven,
    /// which is the sequence a real gesture produces: chord, then the person
    /// carries on typing and navigating.
    func testAnArrowKeyAfterAForgivenChordStillEndsIt() {
        let engine = engine()
        converted(engine)

        tap.send(.chord)
        tap.send(.navigation)
        engine.undoLast()

        XCTAssertEqual(typing.performed.count, 1)
    }

    // MARK: - The shortcut's own chord

    /// The exception, unchanged: the gesture must still be able to fire once.
    func testTheShortcutsOwnChordIsStillForgiven() {
        let engine = engine()
        converted(engine)

        tap.send(.chord)        // the shortcut's keys, seen before Carbon dispatches
        engine.undoLast()       // …and then the action itself

        XCTAssertEqual(typing.performed.count, 2, "the undo shortcut did nothing")
        XCTAssertEqual(typing.performed.last?.insert, "ghbdtn ",
                       "undo puts back what was replaced, ending and all")
    }

    /// And a second chord is not: by then it is somebody navigating with ⌘←
    /// rather than asking for an undo, and the tap cannot tell those apart from
    /// the event alone.
    func testASecondChordIsNotForgiven() {
        let engine = engine()
        converted(engine)

        tap.send(.chord)
        tap.send(.chord)
        engine.undoLast()

        XCTAssertEqual(typing.performed.count, 1)
    }

    // MARK: - What the two events have in common

    /// Both still end the word. The budget is the only thing that distinguishes
    /// them, and a chord that stopped ending the word would put ⌘S's "s" back
    /// in the buffer.
    func testBothEndTheWordAndNeitherConfirmsIt() {
        for event in [TypingBuffer.Event.chord, .navigation] {
            var buffer = TypingBuffer()
            buffer.type("ghbdtn")
            let completion = buffer.accept(event)
            XCTAssertEqual(completion?.word, "ghbdtn", "\(event) did not end the word")
            XCTAssertNil(completion?.ending, "\(event) typed a character into the field")
            XCTAssertFalse(ConversionTriggers.default.converts(event),
                           "\(event) was taken as a confirmation")
        }
    }
}

private extension TypingBuffer {
    mutating func type(_ text: String) {
        for character in text { accept(.character(character)) }
    }
}
