import XCTest
@testable import Module_Layout_Engine

/// «Never this word» is three buttons, and the list must not be able to tell
/// which one was pressed.
///
/// The page's field, the lists window's field and the panel tile's button all
/// ask `Exceptions.adding`, so a word lands as typed, in sorted order, once.
final class ThreeButtonsSpellOneListTests: XCTestCase {

    func testTheWordIsKeptAsItWasTyped() {
        XCTAssertEqual(Exceptions.adding("GHBDTN", to: []), ["GHBDTN"])
    }

    func testTheListComesBackSorted() {
        XCTAssertEqual(Exceptions.adding("apple", to: ["cherry", "banana"]),
                       ["apple", "banana", "cherry"])
    }

    /// The refusal is the point: a caller that cannot tell «added» from «already
    /// there» has to write and announce on every press, and an engine told to
    /// re-read on a press that changed nothing is a round trip for nothing.
    func testAWordAlreadyHeldIsRefused() {
        XCTAssertNil(Exceptions.adding("ghbdtn", to: ["ghbdtn"]))
    }

    /// Case-insensitively, because `Exceptions.contains` is — a list holding
    /// both `Ghbdtn` and `ghbdtn` would be two rows the module reads as one.
    func testTheCaseTypedDoesNotMakeItASecondWord() {
        XCTAssertNil(Exceptions.adding("GHBDTN", to: ["ghbdtn"]))
        XCTAssertNil(Exceptions.adding("  ghbdtn  ", to: ["GHBDTN"]))
    }

    func testAWordThatIsOnlySpaceIsNotAWord() {
        XCTAssertNil(Exceptions.adding("   ", to: []))
        XCTAssertNil(Exceptions.adding("", to: ["a"]))
    }

    /// Trimmed, because a trailing space in a settings field is not a decision —
    /// the same sentence `Exceptions.init` carries, and for the same reason.
    func testTheWordIsTrimmedBeforeItIsStored() {
        XCTAssertEqual(Exceptions.adding("  привет\n", to: []), ["привет"])
    }
}
