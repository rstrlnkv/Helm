import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

// Fakes are per-file, as in every other suite here.

private final class ReachTyping: TypingPort, @unchecked Sendable {
    var performed: [SwitchPlan] = []
    func perform(_ plan: SwitchPlan) -> Bool { performed.append(plan); return true }
}

private final class ReachContext: SecureContextPort, @unchecked Sendable {
    var bundle = "com.apple.Notes"
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { bundle }
}

/// Latin in, Cyrillic of the same grapheme count out. This suite is about how
/// many characters the plan deletes, not about which words a dictionary knows.
private struct ReachTranslation: TranslationPort {
    func translate(_ word: String, from: String, to: String) -> String? {
        guard !word.isEmpty else { return nil }
        return String(repeating: "п", count: word.count)
    }
}

private struct ReachSpell: SpellPort {
    func isWord(_ word: String, sourceID: String) -> Bool? {
        word.unicodeScalars.allSatisfy { $0.value > 0x400 }
    }
}

private final class ReachTap: KeyTapPort, @unchecked Sendable {
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

private final class ReachSources: LayoutSourcePort, @unchecked Sendable {
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) {}
}

/// How far back the gesture reaches, measured against what is actually in the
/// field.
///
/// Every conversion is a blind edit: `SwitchPlan.backspaces` presses of delete
/// sent into a text field Helm cannot read. The automatic path is guarded — the
/// buffer refuses to *report* a word it could not hold in full, and
/// `LayoutEngineEdgeTests.testNoPlanDeletesLessThanWasTyped` pins that. The
/// gesture is a second door into the same arithmetic: `convertLastWord()` reads
/// `buffer.word` directly, and that property answers with whatever prefix the
/// buffer is holding without saying it is a prefix.
final class LayoutEngineGestureReachTests: XCTestCase {
    private var typing = ReachTyping()
    private var context = ReachContext()
    private var tap = ReachTap()

    private func engine() -> LayoutEngine {
        typing = ReachTyping(); context = ReachContext(); tap = ReachTap()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: ReachSources(),
                                  translation: ReachTranslation(), spell: ReachSpell(),
                                  secure: context)
        engine.activate()
        return engine
    }

    /// The trap: mid-word, past the buffer's cap, with the gesture instead of a
    /// space.
    ///
    /// The buffer stops accepting at `maxLength` and the *field* does not. Type
    /// seventy characters and the field holds seventy; the buffer holds
    /// sixty-four and `buffer.word` hands them over as though they were the
    /// whole word. `convertLastWord` converts that prefix with `force: true`,
    /// which skips the dictionary — the one check that might have declined — and
    /// builds a plan for sixty-four backspaces against seventy characters. Six
    /// characters of the original survive, the replacement is typed after them,
    /// and the token is now half Latin and half Cyrillic.
    ///
    /// `TypingBuffer` states the rule in its own comment — "a plan built from a
    /// prefix deletes fewer characters than were typed" — and enforces it only
    /// on the path that returns a `Completion`. `word` is the other path and it
    /// is not marked as poisoned.
    ///
    /// Asserted as a range rather than as a refusal: either answer is a fix.
    /// Refusing is one, and so is holding on to enough to delete all seventy.
    /// What is not a fix is a plan that is *short*.
    func testTheGestureDoesNotConvertAPrefixOfAnOverlongWord() {
        let engine = engine()
        let typed = TypingBuffer.maxLength + 6
        tap.type(String(repeating: "g", count: typed))

        engine.convertLastWord()

        if let plan = typing.performed.first {
            XCTAssertGreaterThanOrEqual(
                plan.backspaces, typed,
                "\(typed) letters are in the field and the gesture deleted "
                + "\(plan.backspaces) of them, then typed \(plan.insert.count) characters "
                + "after the \(typed - plan.backspaces) it left standing")
        }
        withExtendedLifetime(engine) {}
    }

    /// …and the same gesture one character under the cap is still a conversion,
    /// so the answer above is not "refuse everything long".
    func testTheGestureStillConvertsAWordTheBufferHoldsInFull() {
        let engine = engine()
        let typed = TypingBuffer.maxLength - 1
        tap.type(String(repeating: "g", count: typed))
        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1)
        XCTAssertEqual(typing.performed.first?.backspaces, typed)
        withExtendedLifetime(engine) {}
    }

    /// Backspacing out of an overflow does not make the buffer honest again.
    ///
    /// After the cap is passed the buffer has already dropped characters it
    /// never recorded; deleting from the end cannot put them back. The
    /// completion path knows this — `overflowed` survives a backspace and the
    /// next boundary still reports nothing. `buffer.word` forgets it, so the
    /// gesture converts a prefix that is now shorter still.
    ///
    /// Seventy typed, five deleted: the field holds sixty-five characters and
    /// the buffer offers fifty-nine.
    func testBackspacingAfterAnOverflowDoesNotMakeThePrefixConvertible() {
        let engine = engine()
        let typed = TypingBuffer.maxLength + 6
        tap.type(String(repeating: "g", count: typed))
        for _ in 0..<5 { tap.send(.backspace) }

        engine.convertLastWord()

        if let plan = typing.performed.first {
            XCTAssertGreaterThanOrEqual(
                plan.backspaces, typed - 5,
                "\(typed - 5) characters are in the field; the plan deletes \(plan.backspaces)")
        }
        withExtendedLifetime(engine) {}
    }
}
