import XCTest
@testable import Module_Layout_Engine

/// What a shortcut does to the selected text.
///
/// There was no test here at all: three actions were bound to hotkeys, offered
/// in the settings page and shipped, and grepping the suite for
/// `SelectionTransform` returned nothing. Two of the three are gone now, and so
/// is the enum that picked between them — one case, `CaseIterable`, with a
/// struct wrapping one closure so there was something to switch it over. What
/// this pins is the rule that was always the point: trim, ask, and refuse an
/// edit that changes nothing.
final class SelectionTransformTests: XCTestCase {

    /// Stands in for the engine's layout translation, which needs two real
    /// input sources.
    private func transform(_ convert: @escaping @Sendable (String) -> String?)
        -> SelectionTransform {
        SelectionTransform(convert: convert)
    }

    func testConvertingReturnsWhatTheTranslationSays() {
        let subject = transform { $0 == "ghbdtn" ? "привет" : nil }
        XCTAssertEqual(subject.apply(to: "ghbdtn"), "привет")
    }

    /// Nil rather than the same string back. Replacing a selection with itself
    /// is still an edit: it clears the app's undo stack, scrolls the view, and
    /// in some apps drops the selection — three visible consequences for a
    /// keystroke that was meant to do nothing.
    func testAnEditThatChangesNothingIsRefused() {
        let subject = transform { $0 }
        XCTAssertNil(subject.apply(to: "привет"))
    }

    func testNothingSelectedIsNotAnEdit() {
        let subject = transform { _ in "anything" }
        XCTAssertNil(subject.apply(to: ""))
        XCTAssertNil(subject.apply(to: "   \n "))
    }

    /// The translation can decline — no second input source, or a character
    /// that has no twin. A decline is not an edit.
    func testATranslationThatDeclinesMakesNoEdit() {
        let subject = transform { _ in nil }
        XCTAssertNil(subject.apply(to: "ghbdtn"))
    }
}
