import XCTest
@testable import Module_Layout_Engine

/// System-wide secure input is an episode, not a state: a password dialog
/// appears mid-sentence and goes away. What matters is what the engine still
/// holds when it ends.
///
/// The cheap check at the top of `handle` returns early on every secure key —
/// **before** `undo?.invalidate()` runs. So the keystrokes of the password are
/// exactly the ones that never spend the undo, and the only thing standing
/// between an ended dialog and a blind edit replayed across it is that the
/// secure branch clears all three places a word lives, not just the buffer.
/// These two pin that: the sibling `testUndoRestoresTheOriginalOnlyOnce`
/// proves the undo fires without the episode, so a refusal here is the episode
/// and nothing else.
final class ASecureEpisodeLeavesNothingToReplayTests: XCTestCase {

    /// A conversion happened, then a password was typed under secure input.
    /// The dialog moved the caret and the tap never saw it move — the undo is
    /// now a blind edit measured against text that is no longer in front of
    /// the caret, and it must not survive the episode.
    func testAPasswordEpisodeAlsoForgetsTheUndo() {
        let typing = FakeTyping()
        let secure = FakeSecure()
        let tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["ghbdtn": "привет"]),
            spell: FakeSpell(valid: ["привет"]),
            secure: secure, automatic: true)
        engine.activate()

        tap.type("ghbdtn"); tap.space()
        let afterConversion = typing.performed.count
        XCTAssertEqual(afterConversion, 1, "precondition: a conversion happened, so an "
                       + "undo record exists to be forgotten")

        secure.secure = true
        tap.type("hunter2")            // the password; each key returns early
        secure.secure = false

        engine.undoLast()
        XCTAssertEqual(typing.performed.count, afterConversion, """
            the undo survived a secure-input episode: the password's own keystrokes \
            never invalidated it (they return before the invalidate runs), and the \
            replay is a blind edit at a caret the dialog moved.
            """)
        engine.deactivate()
    }

    /// The same episode, one place over: a word typed and ended entirely under
    /// secure input must not be remembered for the gesture. `isSecureInput` is
    /// the system-wide flag, which is a different door from the password-field
    /// role `LayoutEngineStaleWordTests` covers.
    func testAWordTypedUnderSecureInputIsNotTheGesturesToConvert() {
        let typing = FakeTyping()
        let secure = FakeSecure()
        let tap = FakeTap()
        let engine = LayoutEngine(
            tap: tap, typing: typing, sources: FakeSources(current: "en"),
            translation: FakeTranslation(table: ["swordfish": "ыцщквашыр"]),
            spell: FakeSpell(valid: []),
            secure: secure, automatic: false)
        engine.activate()

        secure.secure = true
        tap.type("swordfish"); tap.space()
        secure.secure = false

        engine.convertLastWord()
        XCTAssertTrue(typing.performed.isEmpty, """
            a word typed under system-wide secure input was remembered, and the \
            gesture typed a conversion of it — a password, retyped by Helm into \
            whatever field is focused now.
            """)
        engine.deactivate()
    }
}
