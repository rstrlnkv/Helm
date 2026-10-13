import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The one assertion ported from `TheSearchFieldRestsNarrowerAndWidensOnFocusTests`
/// before that file was deleted along with `ToolbarSearchName`** — every other
/// case in it measured `ToolbarSearchName.size(_:)`, a method that no longer
/// exists: `SettingsToolbar.makeSearchItem`/`patchSearch` pin no resting width
/// to a number: the two constraints `makeSearchItem` builds, `searchRestCap`
/// and `searchOfferCap`, are ceilings, the first switched on by `restSearch(_:)`
/// only while Always Collapse Search is on and the second by
/// `writeSearchOffer(_:tabsWidth:)` only on a bar with a tabs lead, and neither
/// is on in the bar this file builds, so "does it still pin a number" has
/// nothing left in this mechanism to ask. This one case is different — it is
/// a claim about what a person can read once focused, not about the pinning
/// mechanism — and is worth keeping on its own.
///
/// **The owner's order (2026-09-21)**: a focused field has to be wide enough
/// to show a realistic typed query, sized here against "Microsoft Remote
/// Desktop" typed into it — a real 24-character application name — rather
/// than against the prompt it replaces, since a value carries a cancel button
/// a placeholder never draws.
///
/// **The field is the toolbar's.** The width is read off the field of the
/// `NSSearchToolbarItem` on the window's own `NSToolbar`
/// (`LivePageInTheToolbarFixture.searchField`), which `beginSearchInteraction`
/// below opens; a page bar's field would answer the same question about a
/// different control, so the row asserts that the field's delegate is the
/// `SettingsToolbar` the fixture built.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds, which caps an idle field (`searchOfferCap`) and is not
/// read here. **What is pinned.** `setUp` pins through `PinnedBarSettings`:
/// the Flat look, the words-only label style, the module name in the page bar
/// and a search that does not always collapse (`alwaysCollapseSearch` off), so
/// the field this row opens is one that rests at its ordinary width and does
/// not start folded to a magnifier. The field is AppKit's under both looks and
/// the row reads one width against a bare field's, so it is not run under
/// Liquid Glass.
///
/// **What the row prints.** One `[focused search]` line: the focused field's
/// width, the width a bare field needs for the query below, and
/// `window.isKeyWindow` after the interaction began — the row's evidence on
/// whether beginning it turned the window key. On 2026-10-13, Flat, it printed
/// 325.0 pt, 217.5 pt and false.
@MainActor
final class TheFocusedSearchFieldShowsARealisticTypedQueryTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

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
        let fixture = LivePageInTheToolbarFixture(Page(), selection: .module("test.focusedWidth"),
                                                  width: 900, height: 500)
        defer { fixture.drop() }
        fixture.settle(20)
        let field = try XCTUnwrap(fixture.searchField, "no search field in the toolbar")
        XCTAssertTrue(field.delegate === fixture.toolbar, """
            the field is not the one the window's SettingsToolbar built for its search item — the \
            width below would be of another control
            """)
        guard let item = fixture.mount.window?.toolbar?.items
            .compactMap({ $0 as? NSSearchToolbarItem }).first else {
            XCTFail("no search item in the toolbar")
            return
        }
        item.beginSearchInteraction()
        fixture.settle(20)

        // "Microsoft Remote Desktop": a value carries a cancel button a
        // placeholder never draws, which is why the bare field is sized for the
        // typed query and not for the prompt.
        let query = "Microsoft Remote Desktop"
        let needed = naturalWidth(typed: query)
        print("[focused search] field \(field.frame.width) pt, needed \(needed) pt, "
              + "window key: \(fixture.mount.window?.isKeyWindow ?? false)")
        XCTAssertGreaterThanOrEqual(field.frame.width, needed, """
            the field focused to \(field.frame.width) pt, short of the \(needed) pt a bare \
            `NSSearchField` needs to show «\(query)» typed in with its cancel button — a person \
            typing a query that long would not be able to read what they had typed
            """)
    }
}
