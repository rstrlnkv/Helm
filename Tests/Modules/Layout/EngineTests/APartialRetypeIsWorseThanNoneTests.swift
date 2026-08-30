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
/// The one implementation does not keep it. `SynthesisTyping.perform` posts
/// `plan.backspaces` real Delete keystrokes first and only then builds the
/// events for `plan.insert`; the `guard let down = CGEvent(...) else { return
/// false }` inside that second loop is reached with the deletes already gone to
/// the HID tap. `CGEvent(keyboardEventSource:virtualKey:keyDown:)` returns nil
/// on its own — it is a failable allocation against a resource the app does not
/// own — so the reachable outcome is: the word is deleted, nothing is typed in
/// its place, `perform` answers `false`, and the module records the whole thing
/// as «the app refused, nothing to see».
///
/// **The first test in this file is the one to satisfy first, and the order is
/// not a preference.** Tests two, three and four are about the engine trusting
/// `false` too little — it forgets a word the field still holds, and drops an
/// undo the app never carried out. Each is repaired by *keeping* state across a
/// refusal. Do that while `perform` can still half-apply and the kept state is
/// a blind edit measured against text that is no longer there: the gesture then
/// sends seven backspaces into the middle of somebody's sentence, which is
/// strictly worse than the defect being fixed. Make the port all-or-nothing —
/// build every `CGEvent` before posting any of them, as `send(key:)` in the same
/// file already does — and only then let the engine believe `false`.
final class APartialRetypeIsWorseThanNoneTests: XCTestCase {

    // MARK: - The port

    /// The shape the contract requires: nothing is posted until the whole plan
    /// can be posted.
    ///
    /// Read off the source because the failure is unreachable from a test — it
    /// needs `CGEvent(...)` to return nil, which is the system declining an
    /// allocation — and because posting real Delete keystrokes to check would
    /// type into whatever window is in front of the test runner. What is
    /// checkable is the arrangement: a `return false` after the first `.post(`
    /// is the half-applied plan, spelled out.
    func testTheReplacementPostsNothingItCannotFinish() throws {
        let path = "Sources/Modules/Layout/Engine/SystemPorts.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let bodies = SwiftSource.bodiesNamed("perform", in: source)
        XCTAssertEqual(bodies.count, 1,
                       "\(path) no longer holds exactly one perform(_:) — this check has "
                       + "lost its subject and is not guarding anything")
        let body = try XCTUnwrap(bodies.first)
        let firstPost = try XCTUnwrap(
            body.range(of: ".post("),
            "perform(_:) posts nothing at all — the subject of this check is gone")

        let afterTheFirstPost = String(body[firstPost.upperBound...])
        XCTAssertFalse(afterTheFirstPost.contains("return false"), """
            perform(_:) can answer «refused» with keystrokes already posted. The \
            deletes for plan.backspaces go to the HID tap in the first loop; the \
            second loop builds the events for plan.insert and returns false if \
            CGEvent hands back nil. The person watched a word disappear and \
            nothing arrive, and every caller was told nothing happened.
            """)
    }

    // MARK: - The engine, once the port can be believed

    /// A refused conversion, with the field untouched: the word is still on
    /// screen, and Helm has forgotten it.
    ///
    /// What a person does: types `ghbdtn `, sees it stay `ghbdtn ` because the
    /// app declined the synthesised events, and presses the gesture key to fix
    /// it by hand. Nothing happens — not once, not ever, for that word. They
    /// have to delete it and type it again.
    ///
    /// `convert` refuses through `perform`, and `perform` calls
    /// `forgetTheWord()` whether or not anything was typed. Forgetting is right
    /// when the field changed under the module; it is not right when the module
    /// is the one that failed to change it.
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
    /// `undoLast` sets `undo = nil` before it types, and `perform` clears
    /// `lastEvent` on its way through — so a refusal loses both. The page then
    /// shows no last conversion at all, over a field that is still holding the
    /// conversion, and «Never this word» goes with it.
    ///
    /// `TheRefusedChangeStaysOnThePageTests` holds the same promise for the undo
    /// that *worked*: «rejecting a change erased its record». This is the half
    /// where the rejection did not land.
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
    let typing: FieldTyping
    let tap: FieldTap
    let sources = FieldSources()

    init() {
        typing = FieldTyping(field: field)
        tap = FieldTap(field: field)
    }

    func engine() -> LayoutEngine {
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: FieldContext())
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

private final class FieldTyping: TypingPort, @unchecked Sendable {
    private let field: Field
    var performed: [SwitchPlan] = []
    /// One flag, because this suite's subject is the *believed* contract: the
    /// port either did the whole plan or none of it, and `false` means none.
    /// The half-applied state the real port can reach is the first test's
    /// subject and is deliberately not representable here — a fake that could
    /// half-apply would make tests two to four assert something the engine has
    /// no way to know.
    var succeeds = true

    init(field: Field) { self.field = field }

    func perform(_ plan: SwitchPlan) -> Bool {
        performed.append(plan)
        guard succeeds else { return false }
        field.apply(plan)
        return true
    }
}

/// The keystroke reaches the app and then the tap reports it, which is the
/// order `SwitchPlan` is written for — the ending is «the space, the return, the
/// full stop, when the app has already received it».
private final class FieldTap: KeyTapPort, @unchecked Sendable {
    private let field: Field
    var handler: (@Sendable (TypingBuffer.Event) -> Void)?

    init(field: Field) { self.field = field }

    func start(_ onEvent: @escaping @Sendable (TypingBuffer.Event) -> Void,
               onModifier: @escaping @Sendable (ModifierTap.Input) -> Void,
               died: @escaping @Sendable () -> Void) -> Bool {
        handler = onEvent
        return true
    }
    func stop() { handler = nil }

    func type(_ text: String) {
        for character in text {
            field.receive(character)
            handler?(.character(character))
        }
    }
    func space() { field.receive(" "); handler?(.space) }
}

private final class FieldContext: SecureContextPort, @unchecked Sendable {
    func isSecureInput() -> Bool { false }
    func isSecure() -> Bool { false }
    func frontmostBundleID() -> String { "com.apple.Notes" }
}

private final class FieldSources: LayoutSourcePort, @unchecked Sendable {
    var selected: [String] = []
    func installed() -> [String] { ["en", "ru"] }
    func current() -> String? { "en" }
    func select(_ sourceID: String) { selected.append(sourceID) }
}
