import XCTest
@testable import Module_Layout_Engine

/// Which way round to convert a selection.
///
/// For the last word the answer is free: it was typed a moment ago with the
/// current layout active, so the conversion goes from that one to the other.
/// A selection carries no such history — it may have been typed yesterday, by
/// somebody else, in either layout. Deciding by what happens to be active is
/// how "select ghbdtn while Russian is on and press the key" ended up doing
/// nothing at all: Helm asked for Russian → English, and `g` is not on the
/// Russian keyboard, so the translation declined and the app stayed silent.
final class TwoWayConversionTests: XCTestCase {

    /// Latin gibberish while Russian is active: the forward direction has
    /// nothing to say, so the answer is the other one.
    func testItFallsBackToTheOtherDirection() {
        let result = TwoWayConversion.result(for: "ghbdtn",
                                             forward: { _ in nil },
                                             backward: { $0 == "ghbdtn" ? "привет" : nil })
        XCTAssertEqual(result, "привет")
    }

    /// The forward direction is still tried first, and still wins when it works.
    func testTheCurrentLayoutIsAskedFirst() {
        let result = TwoWayConversion.result(for: "руддщ",
                                             forward: { _ in "hello" },
                                             backward: { _ in "never asked" })
        XCTAssertEqual(result, "hello")
    }

    /// A direction that hands back what it was given has not converted
    /// anything, and must not count as an answer — otherwise the app replaces a
    /// selection with itself, which clears the app's undo stack for nothing.
    func testADirectionThatChangesNothingIsNotAnAnswer() {
        let result = TwoWayConversion.result(for: "hello",
                                             forward: { $0 },
                                             backward: { _ in "руддщ" })
        XCTAssertEqual(result, "руддщ")
    }

    /// Neither direction has anything: decline, so the caller leaves the text
    /// alone rather than writing something back.
    func testWhenNeitherDirectionWorksTheAnswerIsNothing() {
        XCTAssertNil(TwoWayConversion.result(for: "12345",
                                             forward: { _ in nil },
                                             backward: { _ in nil }))
        XCTAssertNil(TwoWayConversion.result(for: "hello",
                                             forward: { $0 },
                                             backward: { $0 }))
    }
}
