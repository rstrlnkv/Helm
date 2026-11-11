import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The header row's search submits on Return and on nothing else.** A page's `onSubmit` can start a
/// network query (Homebrew asks brew for a package), so a keystroke, an empty Return or focus leaving the
/// field must never reach it. The guard drives the real field editor, the path a person's typing takes,
/// and reads `onSubmit`'s count: `sendsWholeSearchString` on and `sendsActionOnEndEditing` off are the two
/// settings that keep it so, and the empty-text guard in `Coordinator.submitted(_:)` is the third.
@MainActor
final class TheHeaderSearchSubmitsOnReturnOnlyTests: XCTestCase {

    private final class Page {
        var text = ""
        var submits = 0
    }

    private struct Pane: View {
        let page: Page
        var body: some View {
            Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(search: HelmToolbarSearch(
                    prompt: "Search",
                    text: Binding(get: { page.text }, set: { page.text = $0 }),
                    onSubmit: { page.submits += 1 })))
        }
    }

    private func mounted(_ page: Page) throws -> (LivePageUnderTheHeaderFixture, NSSearchField, NSTextView) {
        let fixture = LivePageUnderTheHeaderFixture(Pane(page: page), selection: .module("test.returnOnly"),
                                                    width: 1060, height: 400)
        fixture.settle(20)
        let field = try XCTUnwrap(fixture.searchField, "the header row holds no search field, so nothing below reads a subject")
        let window = try XCTUnwrap(fixture.mount.window)
        XCTAssertTrue(window.makeFirstResponder(field), "the field would not take focus")
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView, "no field editor, so no keystroke can be delivered")
        return (fixture, field, editor)
    }

    /// Keystrokes through the field editor, then a wait longer than AppKit's own delay for a non-whole-string field.
    func testKeystrokesAndALeftFieldSubmitNothing() throws {
        let page = Page()
        let (fixture, field, editor) = try mounted(page)
        defer { fixture.drop() }
        editor.insertText("wg", replacementRange: editor.selectedRange())
        for _ in 0..<40 { RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.03)) }
        XCTAssertEqual(page.text, "wg", "precondition: the keystrokes did not reach the binding")
        XCTAssertEqual(page.submits, 0, "a keystroke reached onSubmit \(page.submits) times, Return was never pressed")
        XCTAssertTrue(fixture.mount.window?.makeFirstResponder(nil) ?? false, "focus would not leave the field")
        fixture.settle(10)
        XCTAssertEqual(field.stringValue, "wg", "precondition: the word is still in the field")
        XCTAssertEqual(page.submits, 0, "focus leaving the field reached onSubmit \(page.submits) times")
    }

    /// An empty Return is nothing to search for.
    func testReturnOnAnEmptyFieldSubmitsNothing() throws {
        let page = Page()
        let (fixture, _, _) = try mounted(page)
        defer { fixture.drop() }
        XCTAssertTrue(fixture.mount.pressReturn(), "Return never reached the field")
        XCTAssertEqual(page.submits, 0, "Return on an empty field reached onSubmit \(page.submits) times")
    }

    /// The positive half, so the two above are not silent by a Return that never arrives.
    func testReturnOnAWordSubmitsOnce() throws {
        let page = Page()
        let (fixture, _, _) = try mounted(page)
        defer { fixture.drop() }
        XCTAssertTrue(fixture.mount.type("wget"))
        XCTAssertTrue(fixture.mount.pressReturn(), "Return never reached the field")
        XCTAssertEqual(page.submits, 1, "Return on a word reached onSubmit \(page.submits) times, not once")
    }
}
