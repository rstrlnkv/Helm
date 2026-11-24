import HelmTestSupport
import XCTest
import HelmContract
import HelmRuntime
@testable import Module_Layout_Engine

/// How far back the gesture reaches, measured against what is actually in the
/// field.
///
/// Every conversion is a blind edit: `SwitchPlan.backspaces` presses of delete
/// sent into a text field Helm cannot read. The automatic path is guarded — the
/// buffer refuses to *report* a word it could not hold in full, and
/// `LayoutEngineEdgeTests.testNoPlanDeletesLessThanWasTyped` pins that. The
/// gesture is a second door into the same arithmetic, through `convertLastWord()`.
final class LayoutEngineGestureReachTests: XCTestCase {
    private var typing = FakeTyping()
    private var context = FakeSecure()
    private var tap = FakeTap()

    private func engine() -> LayoutEngine {
        typing = FakeTyping(); context = FakeSecure(); tap = FakeTap()
        let engine = LayoutEngine(tap: tap, typing: typing, sources: FakeSources(follows: false),
                                  translation: FakeTranslation(sameLength: true), spell: FakeSpell(cyrillic: true),
                                  secure: context, activation: FakeActivation())
        engine.activate()
        return engine
    }

    /// The trap: mid-word, past the buffer's cap, with the gesture instead of a
    /// space.
    ///
    /// The buffer stops accepting at `maxLength` and the field does not. Type
    /// seventy characters and the buffer holds sixty-four; converted with
    /// `force: true`, which skips the dictionary, a plan for sixty-four
    /// backspaces against seventy characters would leave a token half Latin and
    /// half Cyrillic.
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
    /// next boundary still reports nothing, and the gesture must not convert a
    /// prefix that is now shorter still.
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
