import HelmTestSupport
import XCTest
@testable import Module_Layout_Engine

/// Every key this module synthesises goes out with no modifiers on it.
///
/// **Reported live: «pressing Option converts the word and deletes one more».**
/// `SynthesisTyping.perform` builds its events from
/// `CGEventSource(stateID: .combinedSessionState)`, which carries the *live*
/// modifier state — and the gesture this module ships with is a tap of a
/// modifier. Release ⌥ a moment late and every synthesised Delete goes out as
/// ⌥Delete, which removes a whole word rather than a character: the replacement
/// lands and a word beside it is gone. ⌘ is worse — a synthesised ⌘-letter is a
/// menu command in whatever app is in front.
///
/// `send(key:)` in the same file sets `.maskCommand` deliberately, which is what
/// proves these flags are inherited rather than empty by default.
///
/// **A source-shape check, because the value is not reachable from a test.**
/// Reading the flag off a real event means posting it, and posting a Delete
/// from the test runner types into whatever window is in front. What is
/// checkable is that every event built here is cleared before the loop that
/// posts them — which is exactly what was missing.
final class NoSynthesisedKeyCarriesAHeldModifierTests: XCTestCase {

    func testEverySynthesisedEventHasItsFlagsCleared() throws {
        let path = "Sources/Modules/Layout/Engine/SystemPorts.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let bodies = SwiftSource.bodiesNamed("perform", in: source)
        XCTAssertEqual(bodies.count, 1,
                       "\(path) no longer holds exactly one perform(_:) — this check has lost "
                       + "its subject and is guarding nothing")
        let body = try XCTUnwrap(bodies.first)

        // Two events are built per iteration in each of the two loops, so four
        // `CGEvent(` in total, and each pair must be cleared.
        let built = body.components(separatedBy: "CGEvent(keyboardEventSource:").count - 1
        XCTAssertEqual(built, 4,
                       "perform(_:) builds \(built) keyboard events, not the four this check was "
                       + "measured against — re-read it rather than inherit the number below")

        let cleared = body.components(separatedBy: ".flags = []").count - 1
        XCTAssertEqual(cleared, built, """
            perform(_:) builds \(built) keyboard events and clears the flags on \(cleared) of \
            them. An event that inherits the live modifier state is a Delete that removes a \
            whole word when ⌥ is still held, or a menu command when ⌘ is.
            """)
    }

    /// And the clearing has to happen before anything is posted, or an event
    /// goes out carrying what it was built with.
    func testTheFlagsAreClearedBeforeAnythingIsPosted() throws {
        let path = "Sources/Modules/Layout/Engine/SystemPorts.swift"
        let source = SwiftSource.code(try RepoSource.text(of: path))
        let body = try XCTUnwrap(SwiftSource.bodiesNamed("perform", in: source).first)
        let firstPost = try XCTUnwrap(body.range(of: ".post("),
                                      "perform(_:) posts nothing — the subject is gone")
        let lastClear = try XCTUnwrap(body.range(of: ".flags = []", options: .backwards),
                                      "perform(_:) clears no flags at all")
        XCTAssertLessThan(lastClear.upperBound, firstPost.lowerBound,
                          "an event is posted before the flags are cleared, so it goes out "
                          + "carrying whatever the person was holding")
    }
}
