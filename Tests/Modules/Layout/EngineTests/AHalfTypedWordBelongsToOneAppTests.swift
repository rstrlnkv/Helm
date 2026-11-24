import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// `convertLastWord` has two doors, and both must know which app the word came
/// from.
///
/// Converting a word is a blind edit, correct only in the app the word was
/// measured in (`RememberedWord`). `LayoutEngineStaleWordTests` pins the
/// completed word; `convertLastWord` reaches for the live buffer first:
///
/// ```
/// let live = buffer.wholeWord
/// let previous = lastCompleted
/// if let live { convert(live, trailing: nil, force: true) }
/// else if let previous, previous.belongs(to: bundleID) { … }
/// ```
///
/// A half-typed word never became a `RememberedWord`, so the live branch needs
/// its own app check.
///
/// The tap cannot see the app change: its mask is keyDown, leftMouseDown and
/// flagsChanged, and a click or a chord ends the word and hands it to the
/// pinned branch. The app changing with neither is ordinary: a swipe to another
/// Space, an alert, a call joining, another program calling `activate()`.
@MainActor
final class AHalfTypedWordBelongsToOneAppTests: XCTestCase {
    private var typing = FakeTyping()
    private var secure = FakeSecure()
    private var tap = FakeTap()
    private var sources = FakeSources()

    private func engine() -> LayoutEngine {
        typing = FakeTyping(); secure = FakeSecure(); tap = FakeTap(); sources = FakeSources()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: sources,
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: secure, activation: FakeActivation())
        engine.activate()
        return engine
    }

    /// Two ordinary apps, both allowed: `AppScope` has nothing to say and the
    /// only thing standing between the word and the wrong text field is the
    /// check the live branch does not make. Mail is not blocked by default, so
    /// this is not a test the scope rules can pass on the engine's behalf.
    func testAHalfTypedWordIsNotConvertedIntoTheAppTheKeyboardMovedTo() {
        let engine = engine()
        tap.type("ghbdtn")      // mid-word: nothing has ended it, so nothing pinned it
        XCTAssertTrue(typing.performed.isEmpty, "precondition: nothing has been converted yet")

        // The person is now typing somewhere else, and neither a key nor a left
        // click told the tap about it.
        secure.bundle = "com.apple.Mail"

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            \(typing.performed.first?.backspaces ?? 0) backspaces and \
            \(typing.performed.first.map { "«\($0.insert)»" } ?? "nothing") were typed into \
            an app the word was never in. The completed word carries its app and refuses \
            here; the half-typed one carries none and does not.
            """)
        engine.deactivate()
    }

    /// The positive control: the same half-typed word, still in Notes, is the
    /// gesture's to convert. Without this the refusal above could be the
    /// harness never reaching a conversion at all.
    func testTheSameHalfTypedWordIsStillConvertibleWhereItWasTyped() {
        let engine = engine()
        tap.type("ghbdtn")

        engine.convertLastWord()
        XCTAssertEqual(typing.performed.count, 1,
                       "the harness never converts, so the refusal it asserts proves nothing")
        XCTAssertEqual(typing.performed.first?.backspaces, 6)
        XCTAssertEqual(typing.performed.first?.insert, "привет")
        engine.deactivate()
    }

    /// And the empty bundle id — «no idea which app» — is not a match for
    /// anything, which is the rule `AppScope`, `UndoRecord` and `RememberedWord`
    /// all state. `AppScope` refuses this one on its own; the assertion is here
    /// so the live branch cannot read an empty id as «the same app».
    func testAHalfTypedWordIsNotConvertedWhenNothingIsInFront() {
        let engine = engine()
        tap.type("ghbdtn")
        secure.bundle = ""

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty)
        engine.deactivate()
    }
}
