import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The toolbar's search field has an accessibility name in every state a person can meet it in.**
///
/// The bar read here is the app's `SettingsToolbar` on the `LivePageInTheToolbarFixture`'s window, built with
/// the `.sidebarSeparator` lead: the search item is made by `makeSearchItem` and re-named by `patchSearch`
/// whichever lead the toolbar wears (the lead enters `SettingsToolbar.identifiers(content:style:lead:)`, the
/// name item's container and the tabs' lead, and none of them makes or patches the search item), so a name
/// that holds here is the name the app's own window offers.
/// `SettingsToolbar` builds the `NSSearchToolbarItem` itself and re-patches its accessibility label on every
/// refresh. The states worth proving are: empty, holding a value, forced under AppKit's own collapse floor,
/// and a page change, there and back. A language change is not read here:
/// `TheSearchFieldsNameFollowsALanguageChangeThroughTheNewToolbarTests` reads it on the page bar's field
/// (`MountedPageBar`), and no row reads it on this toolbar's.
@MainActor
final class TheSearchFieldsNameSurvivesEmptyTypedFoldedAndAPageChangeTests: XCTestCase {

    /// The binding's other end, on a class so a fixture can read what was
    /// typed without the page being rebuilt into a new copy of itself.
    private final class Holder {
        var text = ""
    }

    private struct Page: View {
        let prompt: String
        let holder: Holder
        let token: String
        var body: some View {
            Text("the list").frame(maxWidth: .infinity, maxHeight: .infinity)
                .helmWindowToolbar(HelmPageToolbarContent(
                    search: HelmToolbarSearch(
                        prompt: prompt,
                        text: Binding(get: { holder.text }, set: { holder.text = $0 }))),
                    token: token)
        }
    }

    /// What a page change actually is, for one mounted `SettingsToolbar` — a
    /// different page drawn under the same window, the way a person switches
    /// pages in the sidebar. `@Published` rather than a plain `@State` on
    /// `Page` itself: the test drives this from outside the view tree, the
    /// same way `SettingsModel.selection` is driven from outside it.
    private final class PageSwitch: ObservableObject {
        @Published var showsB = false
    }

    private struct SwitchingPage: View {
        @ObservedObject var pageSwitch: PageSwitch
        let holderA: Holder
        let holderB: Holder
        var body: some View {
            if pageSwitch.showsB {
                Page(prompt: "Search hosts", holder: holderB, token: "test.searchPageB")
            } else {
                Page(prompt: "Search apps", holder: holderA, token: "test.searchPageA")
            }
        }
    }

    private var fixtures: [LivePageInTheToolbarFixture] = []

    /// The toolbar reads these when it is built, so they are pinned before a fixture is.
    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        super.tearDown()
    }

    private func mount(token: String) -> (LivePageInTheToolbarFixture, Holder) {
        let holder = Holder()
        let fixture = LivePageInTheToolbarFixture(Page(prompt: "Search apps", holder: holder, token: token),
                                             selection: .module(token), width: 1060, height: 500)
        fixtures.append(fixture)
        fixture.settle(25)
        return (fixture, holder)
    }

    /// The field a `LivePageInTheToolbarFixture` mounted, or a failure that says
    /// there is nothing here to read a name off — never nil quietly.
    private func field(_ fixture: LivePageInTheToolbarFixture, _ what: String,
                       file: StaticString = #filePath, line: UInt = #line) -> NSSearchField? {
        guard let toolbar = fixture.mount.window?.toolbar else {
            XCTFail("""
                \(what): no toolbar on the fixture's window, so there is nothing here whose name \
                could be read — the fixture never attached its `SettingsToolbar`
                """, file: file, line: line)
            return nil
        }
        guard let field = fixture.searchField else {
            XCTFail("""
                \(what): the toolbar holds no search field at all (it lists \
                \(toolbar.items.map(\.itemIdentifier.rawValue))), so there is nothing here whose \
                name could be read — either the page's declare never reached the channel or \
                `SettingsToolbar` stopped publishing the item
                """, file: file, line: line)
            return nil
        }
        return field
    }

    // MARK: - Empty

    func testAnEmptyFieldHasAName() throws {
        let (fixture, _) = mount(token: "test.searchEmpty")
        let field = try XCTUnwrap(field(fixture, "empty"))
        XCTAssertEqual(field.placeholderString, "Search apps",
                       "precondition: the prompt never reached the field")
        XCTAssertFalse(field.isHidden, "precondition: with the setting off the empty field rests open")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the search field is read aloud with no name — `makeSearchItem` set none, or \
            `patchSearch` overwrote it with nothing on the refresh that follows every declare
            """)
    }

    // MARK: - With a value

    /// Typed rather than assigned: `controlTextDidChange` is `SettingsToolbar`'s
    /// own delegate method, and posting the notification the way AppKit does is
    /// what actually exercises it, the way a keystroke reaches it.
    func testAFieldWithSomethingInItStillHasAName() throws {
        let (fixture, holder) = mount(token: "test.searchTyped")
        let field = try XCTUnwrap(field(fixture, "with a value"))
        field.stringValue = "wget"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        fixture.settle(10)
        XCTAssertEqual(holder.text, "wget", "precondition: the value never reached the binding")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the field has a value and no name — a prompt is what AppKit drops first, \
            and a field holding a value has none to fall back on
            """)
    }

    // MARK: - Collapsed

    /// Forced directly under AppKit's own collapse floor — a bare toolbar with nothing beside the field
    /// rests open at any width this fixture can reach, so reaching the collapsed state honestly needs a
    /// crowded bar this file has no reason to build. Every width constraint on the field is dropped, whichever
    /// of `SettingsToolbar` or AppKit put it there, and a 40 pt one is put in their place.
    private func forceCollapsed(_ field: NSSearchField, _ fixture: LivePageInTheToolbarFixture) {
        field.constraints
            .filter { $0.firstItem === field && $0.firstAttribute == .width }
            .forEach { $0.isActive = false }
        field.widthAnchor.constraint(equalToConstant: 40).isActive = true
        fixture.settle(15)
    }

    func testTheCollapsedControlsFieldHasAName() throws {
        let (fixture, _) = mount(token: "test.searchCollapsed")
        let field = try XCTUnwrap(field(fixture, "collapsed"))
        forceCollapsed(field, fixture)
        XCTAssertTrue(field.isHidden, """
            precondition: the field is still visible after forcing its width under 160 pt — \
            AppKit's own floor moved, and this fixture's forcing needs to move with it
            """)
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the collapsed search's hidden field has no name
            """)
    }

    // MARK: - A page change

    /// A page change here means a different page — one with its own token —
    /// drawn under the *same* `LivePageInTheToolbarFixture`, the same window and
    /// the same `SettingsToolbar`: switching `pageSwitch.showsB` swaps which
    /// page `SwitchingPage` draws, and `model.selection` moves with it, the
    /// way `SettingsWindow` moves both together on a sidebar click. Two
    /// independent fixtures, each with its own toolbar, proved nothing about
    /// a page change at all — `SettingsToolbar` caches one `NSToolbar` per
    /// page keyed on its own `pageBars`, and a second fixture never touches
    /// the first one's cache either way.
    func testTheNameSurvivesAPageChange() throws {
        let holderA = Holder(), holderB = Holder()
        let pageSwitch = PageSwitch()
        let fixture = LivePageInTheToolbarFixture(SwitchingPage(pageSwitch: pageSwitch, holderA: holderA,
                                                           holderB: holderB),
                                             selection: .module("test.searchPageA"),
                                             width: 1060, height: 500)
        fixtures.append(fixture)
        fixture.settle(25)

        let fieldA = try XCTUnwrap(field(fixture, "page A"))
        XCTAssertEqual(fieldA.placeholderString, "Search apps", "precondition: page A's prompt never arrived")
        XCTAssertEqual(fieldA.accessibilityLabel(), HelmA11y.searchField,
                       "precondition: page A's own field starts unnamed")

        // Taken off while page A is on screen, so the only thing that can name it again is the patch
        // `SettingsToolbar` makes when page A comes back to the window.
        fieldA.setAccessibilityLabel(nil)
        XCTAssertNil(fieldA.accessibilityLabel(), "precondition: the field's name was not taken off")

        pageSwitch.showsB = true
        fixture.model.selection = .module("test.searchPageB")
        fixture.settle(25)

        let fieldB = try XCTUnwrap(field(fixture, "page B"))
        XCTAssertEqual(fieldB.placeholderString, "Search hosts",
                       "precondition: page B's declaration never reached its field")
        XCTAssertFalse(fieldA === fieldB, """
            precondition: the same field object came back for a different page, so this case \
            proves nothing about a field built fresh
            """)
        XCTAssertEqual(fieldB.accessibilityLabel(), HelmA11y.searchField, """
            the field built for the second page has no name — a one-off naming would leave \
            every page but the first without one
            """)

        // Page B is on the window and page A is not: nothing has named page A's field in the meantime.
        XCTAssertNil(fieldA.accessibilityLabel(), """
            page A's field was named while page A was away, so the return below cannot tell a name \
            put on at the return from one put on earlier
            """)

        // And back: page A's cached bar returns with its own field, which is still unnamed, and the
        // name is put on it again.
        pageSwitch.showsB = false
        fixture.model.selection = .module("test.searchPageA")
        fixture.settle(25)

        let fieldAgain = try XCTUnwrap(field(fixture, "page A again"))
        XCTAssertEqual(fieldAgain.placeholderString, "Search apps",
                       "precondition: page A's prompt did not come back with the page")
        XCTAssertTrue(fieldAgain === fieldA, """
            precondition: page A did not come back with its own field, so this case proves nothing \
            about a field that was left unnamed
            """)
        XCTAssertEqual(fieldAgain.accessibilityLabel(), HelmA11y.searchField, """
            the field of a page that came back has no name — what was taken off it before the page \
            left was never put on again
            """)
    }
}
