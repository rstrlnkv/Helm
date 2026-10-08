import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The one assertion ported from `TheSearchFieldRestsNarrowerAndWidensOnFocusTests`
/// before that file was deleted along with `ToolbarSearchName`** — every other
/// case in it measured `ToolbarSearchName.size(_:)`, a method that no longer
/// exists: the page bar takes the search's widths from `ShellBarLayout`
/// (`searchWidth`, `searchFloor`, and `magnifierWidth` at rest under
/// `alwaysCollapseSearch`), so nothing is left of that mechanism to ask about. This one case is different — it is
/// a claim about what a person can read once focused, not about the pinning
/// mechanism — and is worth keeping on its own.
///
/// **The owner's order (2026-09-21)**: a focused field has to be wide enough
/// to show a realistic typed query, sized here against "Microsoft Remote
/// Desktop" typed into it — a real 24-character application name — rather
/// than against the prompt it replaces, since a value carries a cancel button
/// a placeholder never draws.
///
/// **The field starts as its magnifier.** With `alwaysCollapseSearch` on, the zone rests as a
/// magnifier `ShellBarLayout.magnifierWidth` wide and a press on it opens the field and focuses it, so
/// the width read is the one the bar gave the field after that press, from the real bar the
/// `LivePageToolbarFixture` put in the window. The field's own width, not the plate's.
@MainActor
final class TheFocusedSearchFieldShowsARealisticTypedQueryTests: XCTestCase {

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?

    /// The bar reads these when it is built, so they are pinned before a fixture is and put back after.
    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.barAppearance = .flat
        AppSettings.alwaysCollapseSearch = true
    }

    override func tearDown() {
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
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
        let fixture = LivePageToolbarFixture(Page(), selection: .module("test.focusedWidth"),
                                             width: 900, height: 500)
        defer { fixture.drop() }
        fixture.settle(20)
        let field = try XCTUnwrap(fixture.mount.searchField, "no search field in the bar")
        let zone = fixture.pageBar.search
        XCTAssertTrue(field === zone.field, "precondition: the field found in the window is not the zone's")
        XCTAssertTrue(field.isHidden, "precondition: the empty field is not resting as the magnifier")
        XCTAssertEqual(zone.plate.frame.width, ShellBarLayout.magnifierWidth,
                       "precondition: the plate is not the magnifier's width before the press")
        zone.magnifier.performClick(nil)
        fixture.settle(20)
        XCTAssertFalse(field.isHidden, "precondition: the magnifier's press did not open the field")
        XCTAssertNotNil(field.currentEditor(), "precondition: the opened field never took editing")

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
