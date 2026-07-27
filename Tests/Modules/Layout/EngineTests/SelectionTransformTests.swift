import XCTest
@testable import Module_Layout_Engine

/// What a shortcut does to the selected text.
///
/// There was no test here at all: three actions were bound to hotkeys, offered
/// in the settings page and shipped, and grepping the suite for
/// `SelectionTransform` returned nothing. Two of the three are gone now; this
/// pins the one that stays, and the refusal that makes it safe to put on a key.
final class SelectionTransformTests: XCTestCase {

    /// Stands in for the engine's layout translation, which needs two real
    /// input sources.
    private func transform(_ convert: @escaping @Sendable (String) -> String?)
        -> SelectionTransform {
        SelectionTransform(convert: convert)
    }

    func testConvertingReturnsWhatTheTranslationSays() {
        let subject = transform { $0 == "ghbdtn" ? "привет" : nil }
        XCTAssertEqual(subject.apply(.convert, to: "ghbdtn"), "привет")
    }

    /// Nil rather than the same string back. Replacing a selection with itself
    /// is still an edit: it clears the app's undo stack, scrolls the view, and
    /// in some apps drops the selection — three visible consequences for a
    /// keystroke that was meant to do nothing.
    func testAnEditThatChangesNothingIsRefused() {
        let subject = transform { $0 }
        XCTAssertNil(subject.apply(.convert, to: "привет"))
    }

    func testNothingSelectedIsNotAnEdit() {
        let subject = transform { _ in "anything" }
        XCTAssertNil(subject.apply(.convert, to: ""))
        XCTAssertNil(subject.apply(.convert, to: "   \n "))
    }

    /// The translation can decline — no second input source, or a character
    /// that has no twin. A decline is not an edit.
    func testATranslationThatDeclinesMakesNoEdit() {
        let subject = transform { _ in nil }
        XCTAssertNil(subject.apply(.convert, to: "ghbdtn"))
    }

    /// One case, so the enum cannot silently regrow the two that were removed
    /// for being unsafe or redundant.
    func testConvertIsTheOnlyAction() {
        XCTAssertEqual(SelectionAction.allCases, [.convert])
    }
}
