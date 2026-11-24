import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// One contract, and the four things that lean on it.
///
/// `TypingPort.perform` is documented as **«False when the target refused the
/// events; a partial retype is worse than none»**, and `LayoutEngine.convert`
/// spends that promise by name: «The port's own contract says a refusal means
/// the text was not replaced.» Every caller of `perform` reads `false` as
/// «nothing happened» — no undo recorded, no input source switched, nothing
/// counted, a warning logged and the word dropped.
///
/// `SynthesisTyping.perform` keeps it: every `CGEvent` for the plan is built
/// before any is posted (`CGEvent(keyboardEventSource:virtualKey:keyDown:)` is
/// a failable allocation), so `false` means the field is untouched.
///
/// The tests below hold the engine to believing that: it keeps a word the
/// field still holds, and an undo the app never carried out. Kept state across
/// a refusal is safe only because the port cannot half-apply; otherwise it
/// would be a blind edit against text that is no longer there.
final class APartialRetypeIsWorseThanNoneTests: XCTestCase {

    // MARK: - The engine, once the port can be believed

    /// A refused conversion, with the field untouched: the word is still on
    /// screen, and Helm has forgotten it.
    ///
    /// What a person does: types `ghbdtn `, sees it stay `ghbdtn ` because the
    /// app declined the synthesised events, and presses the gesture key to fix
    /// it by hand. The word must still be there to fix.
    ///
    /// Forgetting is right when the field changed under the module; it is not
    /// right when the module is the one that failed to change it.
    func testAWordTheAppRefusedIsStillTheGesturesToConvert() {
        let world = World()
        let engine = world.engine()
        world.typing.succeeds = false
        world.field.text = "note: "
        world.tap.type("ghbdtn")
        world.tap.space()
        XCTAssertEqual(world.field.text, "note: ghbdtn ",
                       "precondition: the app refused, so the field is as it was")
        XCTAssertEqual(world.typing.performed.count, 1,
                       "precondition: a plan was built and offered")
        XCTAssertEqual(world.sources.selected, [],
                       "precondition: a refusal does not switch the keyboard either — the "
                       + "whole conversion did not happen")

        world.typing.succeeds = true
        engine.convertLastWord()
        XCTAssertEqual(world.field.text, "note: привет ", """
            the gesture had nothing to work on: the refused conversion dropped a \
            word that never left the field, so the one key that exists to fix a \
            word by hand is dead on exactly the word that needed it.
            """)
        engine.deactivate()
    }

    /// A refused undo, and the row that says what happened.
    ///
    /// A refusal keeps both the undo and `lastEvent`, or the page shows no last
    /// conversion over a field still holding it, and «Never this word» goes
    /// with it.
    func testARefusedUndoLeavesTheChangeOnThePage() async {
        let world = World()
        let engine = world.engine()
        world.field.text = "note: "
        world.tap.type("ghbdtn")
        world.tap.space()
        XCTAssertEqual(world.field.text, "note: привет ", "precondition: the word was converted")
        let converted = await latestLayoutState(engine)
        XCTAssertEqual(converted?.lastConversion?.before, "ghbdtn",
                       "precondition: the change reached the page")

        world.typing.succeeds = false
        engine.undoLast()
        XCTAssertEqual(world.field.text, "note: привет ",
                       "precondition: the app refused, so the conversion still stands")
        XCTAssertEqual(world.sources.selected, ["ru"],
                       "precondition: the keyboard was not put back either, which is right — "
                       + "both halves of an undo or neither")

        let refused = await latestLayoutState(engine)
        XCTAssertEqual(refused?.lastConversion?.before, "ghbdtn", """
            the page forgot a conversion that is still in the field, because the \
            undo of it was refused. The row and its «Never this word» button are \
            gone while the word they describe is on screen.
            """)
        engine.deactivate()
    }

    /// …and the key can be pressed again.
    ///
    /// The gesture is one key that undoes if it can and converts otherwise. A
    /// refusal that drops the record does not just lose one press: the next
    /// press falls through to the convert half, which has been forgotten too, so
    /// the key does nothing at all in an app that is still holding the change.
    func testARefusedUndoCanBeTriedAgain() {
        let world = World()
        let engine = world.engine()
        world.field.text = "note: "
        world.tap.type("ghbdtn")
        world.tap.space()
        XCTAssertEqual(world.field.text, "note: привет ", "precondition: the word was converted")

        world.typing.succeeds = false
        engine.undoLast()
        world.typing.succeeds = true
        engine.undoLast()
        XCTAssertEqual(world.field.text, "note: ghbdtn ", """
            the second press did nothing: the first, which the app refused, had \
            already thrown the record away. One declined press retires the undo \
            for good.
            """)
        engine.deactivate()
    }
}

// MARK: - A field the plan is applied to

/// The ports, with the plan actually carried out against a string.
///
/// The suite's `FakeTyping` records plans and answers a flag; that is enough to
/// ask «was a plan built», and it cannot answer «what is in the field now»,
/// which is the only question these four tests have.
private final class World {
    let field = Field()
    let typing = FakeTyping()
    let tap = FakeTap()
    let sources = FakeSources(follows: false)

    init() {
        let field = field
        typing.apply = { field.apply($0) }
        tap.received = { field.receive($0) }
    }

    func engine() -> LayoutEngine {
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FakeSecure(), activation: FakeActivation())
        engine.activate()
        return engine
    }
}

/// What the app is holding. One object both fakes write to, because a test that
/// gave the tap and the typing port a field each would be asserting about two
/// strings that never meet.
private final class Field: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var text: String {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); storage = newValue; lock.unlock() }
    }

    func receive(_ character: Character) { text.append(character) }

    func apply(_ plan: SwitchPlan) {
        var current = text
        for _ in 0..<plan.backspaces where !current.isEmpty { current.removeLast() }
        text = current + plan.insert
    }
}

