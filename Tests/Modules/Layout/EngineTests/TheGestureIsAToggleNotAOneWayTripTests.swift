import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// Tap, tap, tap: convert, put back, convert again.
///
/// **Reported live, and the log had counted it exactly.** Type `d`, tap the
/// bound key and get `в`; tap again and get `d` back; tap a third time and
/// nothing happens — nor on the twelve taps after it. The log held fifteen
/// «gesture: last word» lines against a single conversion.
///
/// `undoLast` puts the text back through `perform`, and `perform` calls
/// `forgetTheWord()` on success — buffer, remembered word and undo record all
/// gone. So after an undo the module held no handle at all on text it had
/// typed itself a moment earlier, and every further tap reached `fix()`, found
/// nothing, and returned in silence.
///
/// It knows what is in the field, because it put it there: the word it just
/// restored, in the app it restored it in.
final class TheGestureIsAToggleNotAOneWayTripTests: XCTestCase {

    private var typing = ToggleTyping()
    private var tap = ToggleTap()
    private var context = ToggleContext()
    private var sources = ToggleSources()

    private func engine() -> LayoutEngine {
        typing = ToggleTyping(); tap = ToggleTap()
        context = ToggleContext(); sources = ToggleSources()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: ToggleTranslation(), spell: ToggleSpell(),
                                  secure: context)
        engine.activate()
        return engine
    }

    func testAThirdTapConvertsAgain() {
        let engine = engine()
        tap.type("d")
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.map(\.insert), ["в"],
                       "precondition: the first tap did not convert")

        engine.undoLast()
        XCTAssertEqual(typing.performed.map(\.insert), ["в", "d"],
                       "precondition: the second tap did not put the word back")

        engine.convertLastWord()
        XCTAssertEqual(typing.performed.map(\.insert), ["в", "d", "в"],
                       "the third tap did nothing: the undo forgot the word it had just typed "
                       + "into the field, so the gesture had no handle on it")
    }

    /// And the fourth takes it back again — a toggle, not two steps and a dead
    /// end. This is the half that would fail if the repair remembered the word
    /// but left no undo behind it.
    func testAndTheFourthTapPutsItBack() {
        let engine = engine()
        tap.type("d")
        engine.convertLastWord()
        engine.undoLast()
        engine.convertLastWord()
        engine.undoLast()
        XCTAssertEqual(typing.performed.map(\.insert), ["в", "d", "в", "d"],
                       "the fourth tap did not put the word back")
    }

    /// The word comes back tied to the app it was restored in, like every other
    /// blind edit this module keeps: `RememberedWord.belongs(to:)` is the same
    /// check `UndoRecord.canUndo(in:)` makes, and for the same reason.
    func testTheRestoredWordBelongsToTheAppItWasRestoredIn() {
        let engine = engine()
        tap.type("d")
        engine.convertLastWord()
        engine.undoLast()
        context.bundle = "com.apple.mail"
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 2,
                       "the restored word was converted in an app it was never typed in")
    }
}

// MARK: - Ports

private final class ToggleTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class ToggleTap: KeyTapPort, @unchecked Sendable {
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?
    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        handler = onEvent
        return true
    }
    func stop() { handler = nil }
    func type(_ text: String) { for character in text { handler?(.character(character)) } }
}

private final class ToggleContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { bundle }
}

private final class ToggleSources: LayoutSourcePort, @unchecked Sendable {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

private struct ToggleTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        let table: [Character: Character] = ["d": "в", "в": "d"]
        let out = String(word.map { table[$0] ?? $0 })
        return out == word ? nil : out
    }
}

private struct ToggleSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? { word == "в" }
}
