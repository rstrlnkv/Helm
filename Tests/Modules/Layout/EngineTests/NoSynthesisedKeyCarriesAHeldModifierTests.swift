import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// Every key this module synthesises goes out with no modifiers on it.
///
/// **Reported live: «pressing Option converts the word and deletes one more».**
/// `SynthesisTyping.events(for:)` builds its events from
/// `CGEventSource(stateID: .combinedSessionState)`, which carries the *live*
/// modifier state — and the gesture this module ships with is a tap of a
/// modifier. Release ⌥ a moment late and every synthesised Delete goes out as
/// ⌥Delete, which removes a whole word rather than a character: the replacement
/// lands and a word beside it is gone. ⌘ is worse — a synthesised ⌘-letter is a
/// menu command in whatever app is in front.
///
/// `SystemCommandKeys.press` in the same file sets `.maskCommand` deliberately, which is what
/// proves these flags are inherited rather than empty by default.
///
/// **A source-shape check, because the value is not reachable from a test.**
/// Reading the flag off a real event means posting it, and posting a Delete
/// from the test runner types into whatever window is in front. What is
/// checkable is that every event built here is cleared, and that the builder
/// posts nothing itself — which is exactly what was missing.
final class NoSynthesisedKeyCarriesAHeldModifierTests: XCTestCase {

    func testEverySynthesisedEventHasItsFlagsCleared() throws {
        let path = "Sources/Modules/Layout/Engine/SystemPorts.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let bodies = SwiftSource.bodiesNamed("events", in: source)
        XCTAssertEqual(bodies.count, 1,
                       "\(path) no longer holds exactly one events(for:) — this check has lost "
                       + "its subject and is guarding nothing")
        let body = try XCTUnwrap(bodies.first)

        // Two events are built per iteration in each of the two loops, so four
        // `CGEvent(` in total, and each pair must be cleared.
        let built = body.components(separatedBy: "CGEvent(keyboardEventSource:").count - 1
        XCTAssertEqual(built, 4,
                       "events(for:) builds \(built) keyboard events, not the four this check was "
                       + "measured against — re-read it rather than inherit the number below")

        let cleared = body.components(separatedBy: ".flags = []").count - 1
        XCTAssertEqual(cleared, built, """
            events(for:) builds \(built) keyboard events and clears the flags on \(cleared) of \
            them. An event that inherits the live modifier state is a Delete that removes a \
            whole word when ⌥ is still held, or a menu command when ⌘ is.
            """)
    }

    /// The builder posts nothing and `perform` builds nothing, so no event goes
    /// out that the builder did not clear.
    func testNothingIsPostedThatTheBuilderDidNotClear() throws {
        let path = "Sources/Modules/Layout/Engine/SystemPorts.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let builder = try XCTUnwrap(SwiftSource.bodiesNamed("events", in: source).first)
        XCTAssertFalse(builder.contains(".post("),
                       "events(for:) posts: an event would go out before the caller sees it")
        let perform = try XCTUnwrap(SwiftSource.bodiesNamed("perform", in: source).first,
                                    "perform(_:) is gone — the subject is gone")
        XCTAssertTrue(perform.contains(".post("), "perform(_:) posts nothing — the subject is gone")
        XCTAssertFalse(perform.contains("CGEvent("),
                       "perform(_:) builds an event of its own that events(for:) never cleared")
    }
}
