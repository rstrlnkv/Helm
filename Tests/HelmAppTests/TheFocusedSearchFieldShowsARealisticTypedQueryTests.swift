import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The one assertion ported from `TheSearchFieldRestsNarrowerAndWidensOnFocusTests`
/// before that file was deleted along with `ToolbarSearchName`** — every other
/// case in it measured `ToolbarSearchName.size(_:)`, a method that no longer
/// exists: `SettingsToolbar.makeSearchItem`/`patchSearch` never pin a resting
/// width at all, pinned or otherwise, so "does it still pin a number" has
/// nothing left in this mechanism to ask. This one case is different — it is
/// a claim about what a person can read once focused, not about the pinning
/// mechanism — and is worth keeping on its own.
///
/// **The owner's order (2026-09-21)**: a focused field has to be wide enough
/// to show a realistic typed query, sized here against "Microsoft Remote
/// Desktop" typed into it — a real 24-character application name — rather
/// than against the prompt it replaces, since a value carries a cancel button
/// a placeholder never draws.
@MainActor
final class TheFocusedSearchFieldShowsARealisticTypedQueryTests: XCTestCase {

    private struct Page: View {
        var body: some View {
            Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(search: HelmToolbarSearch(
                    prompt: "Search apps", text: .constant(""))), token: "test.focusedWidth")
        }
    }

    /// What AppKit itself gives a bare, unmounted `NSSearchField` sized for
    /// typed content — never mounted, never drawn. The mounted control's
    /// focused width is checked against this rather than against a written
    /// number, so the check is of the arithmetic and not of a copy of its
    /// answer.
    private func naturalWidth(typed: String) -> CGFloat {
        let probe = NSSearchField()
        probe.stringValue = typed
        probe.sizeToFit()
        return probe.frame.width
    }

    func testTheFocusedWidthShowsARealisticTypedQuery() throws {
        let fixture = LivePageToolbarFixture(Page(), selection: .module("test.focusedWidth"),
                                             width: 900, height: 500)
        defer { fixture.drop() }
        fixture.settle(20)
        let field = try XCTUnwrap(fixture.mount.searchField, "no search field in the toolbar")
        guard let item = fixture.mount.window?.toolbar?.items
            .compactMap({ $0 as? NSSearchToolbarItem }).first else {
            XCTFail("no search item in the toolbar")
            return
        }
        item.beginSearchInteraction()
        fixture.settle(20)

        // "Microsoft Remote Desktop": measured, a value carries a cancel
        // button a placeholder never draws — "Search apps" sizes to 108 pt as
        // a placeholder against 132 pt typed in, a 24 pt difference that is
        // exactly that button.
        let query = "Microsoft Remote Desktop"
        let needed = naturalWidth(typed: query)
        XCTAssertGreaterThanOrEqual(field.frame.width, needed, """
            the field focused to \(field.frame.width) pt, short of the \(needed) pt a bare \
            `NSSearchField` needs to show «\(query)» typed in with its cancel button — a person \
            typing a query that long would not be able to read what they had typed
            """)
    }
}
