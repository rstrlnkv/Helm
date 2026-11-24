import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// Tap, tap, tap: convert, put back, convert again.
///
/// Type `d`, tap the bound key and get `в`; tap again and get `d` back; a third
/// tap converts again. `perform` forgets the word on success, so after an undo
/// the module keeps what it knows is in the field because it put it there: the
/// word it just restored, in the app it restored it in.
final class TheGestureIsAToggleNotAOneWayTripTests: XCTestCase {

    private var typing = FakeTyping()
    private var tap = FakeTap()
    private var context = FakeSecure()
    private var sources = FakeSources(follows: false)

    private func engine() -> LayoutEngine {
        typing = FakeTyping(); tap = FakeTap()
        context = FakeSecure(); sources = FakeSources(follows: false)
        let engine = LayoutEngine(tap: tap, typing: typing, sources: sources,
                                  translation: FakeTranslation(otherwise: { word, _, _ in
                                      let table: [Character: Character] = ["d": "в", "в": "d"]
                                      let out = String(word.map { table[$0] ?? $0 })
                                      return out == word ? nil : out }),
                                  spell: FakeSpell(valid: ["в"]),
                                  secure: context, activation: FakeActivation())
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
