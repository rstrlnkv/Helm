import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// **`convertLastWord` has two doors and only one of them knows which app the
/// word came from.**
///
/// The module's own rule, written out at length on `RememberedWord`: converting
/// a word is a blind edit — a fixed count of backspaces sent at whatever the
/// caret is in front of now — and it is only correct in the app the word was
/// measured in. «Type `ghbdtn` in Notes, switch to Mail, tap the key, and six
/// backspaces and a Russian word land in Mail» is that file's own example, and
/// `belongs(to:)` is the repair. `LayoutEngineStaleWordTests` pins it.
///
/// It pins the *completed* word. `convertLastWord` reaches for the live buffer
/// first:
///
/// ```
/// let live = buffer.wholeWord
/// let previous = lastCompleted
/// if let live { convert(live, trailing: nil, force: true) }
/// else if let previous, previous.belongs(to: bundleID) { … }
/// ```
///
/// `buffer` carries no app, so the branch that runs first is the branch with no
/// check. A word half typed — nothing has ended it, so it never became a
/// `RememberedWord` at all — is converted into whatever is in front when the key
/// is tapped.
///
/// **The tap cannot see this happen.** Its mask is keyDown, leftMouseDown and
/// flagsChanged. A click gives `.click` and a chord gives `.chord`, and both end
/// the word and hand it to the pinned branch — which is why the existing suite,
/// which switches apps with `.chord`, is green. The app changing with neither is
/// ordinary: a four-finger swipe to a Space with another app in front, or any
/// app bringing itself forward — an alert, a call joining, a download opening,
/// another program calling `activate()`. Nothing in that list is a keystroke or
/// a left click, so the buffer survives it intact and unpinned.
///
/// Pinning the buffer to the app it was typed in is one repair; refusing the
/// live branch outside that app is another. Either answers this.
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
            secure: secure)
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
        engine.deactivate()   // drops the didBecomeActive observer this test registered
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
        engine.deactivate()   // drops the didBecomeActive observer this test registered
    }

    /// And the empty bundle id — «no idea which app» — is not a match for
    /// anything, which is the rule `AppScope`, `UndoRecord` and `RememberedWord`
    /// all state and the live branch never reaches. `AppScope` refuses this one
    /// on its own today; the assertion is here so a repair that pins the buffer
    /// cannot accidentally read an empty id as «the same app».
    func testAHalfTypedWordIsNotConvertedWhenNothingIsInFront() {
        let engine = engine()
        tap.type("ghbdtn")
        secure.bundle = ""

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty)
        engine.deactivate()   // drops the didBecomeActive observer this test registered
    }
}
