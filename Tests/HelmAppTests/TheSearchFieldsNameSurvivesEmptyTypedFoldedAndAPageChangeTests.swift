import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Ported from `ASearchFieldSaysWhatItIsTests`, deleted in this pass along
/// with `ToolbarSearchName` — the SwiftUI-bridge-era mechanism it watched.**
///
/// The search field is no longer bridged in from `.searchable`; `SettingsToolbar`
/// builds the `NSSearchToolbarItem` itself (`makeSearchItem`) and re-patches its
/// accessibility label on every refresh (`patchSearch`). What used to need a
/// dedicated namer object to reach the field from outside its own view tree is
/// now a plain method on the object that already owns the item, but the states
/// worth proving are the same ones `ASearchFieldSaysWhatItIsTests` proved against
/// the bridge: empty, holding a value, forced under AppKit's own 160 pt collapse
/// floor, and rebuilt by a page change. "Today's language" and "after a language
/// notice" are already covered, by
/// `TheSearchFieldsNameFollowsALanguageChangeThroughTheNewToolbarTests`, and are
/// not repeated here.
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

    private var fixtures: [LivePageToolbarFixture] = []

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        super.tearDown()
    }

    private func mount(token: String, prompt: String = "Search apps",
                       width: CGFloat = 1060) -> (LivePageToolbarFixture, Holder) {
        let holder = Holder()
        let fixture = LivePageToolbarFixture(Page(prompt: prompt, holder: holder, token: token),
                                             selection: .module(token), width: width, height: 500)
        fixtures.append(fixture)
        fixture.settle(25)
        return (fixture, holder)
    }

    /// The field a `LivePageToolbarFixture` mounted, or a failure that says
    /// there is nothing here to read a name off — never nil quietly.
    private func field(_ fixture: LivePageToolbarFixture, _ what: String,
                       file: StaticString = #filePath, line: UInt = #line) -> NSSearchField? {
        guard let field = fixture.mount.searchField else {
            XCTFail("""
                \(what): the toolbar holds no search field at all, so there is nothing here \
                whose name could be read — either the page's declare never reached the \
                channel or `SettingsToolbar` stopped publishing the item
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
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the search field is read aloud with no name — `makeSearchItem` set none, or \
            `patchSearch` overwrote it with nothing on the refresh that follows every declare
            """)
    }

    // MARK: - With a value

    /// Typed rather than assigned: `controlTextDidChange` is `SettingsToolbar`'s
    /// own delegate method, and posting the notification the way AppKit does is
    /// what actually exercises it, the same device `ASearchFieldSaysWhatItIsTests`
    /// used against the bridge.
    func testAFieldWithSomethingInItStillHasAName() throws {
        let (fixture, holder) = mount(token: "test.searchTyped")
        let field = try XCTUnwrap(field(fixture, "with a value"))
        field.stringValue = "wget"
        NotificationCenter.default.post(name: NSControl.textDidChangeNotification, object: field)
        fixture.settle(10)
        XCTAssertEqual(holder.text, "wget", "precondition: the value never reached the binding")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the field has a value and no name — which is the defect this file's ancestor was \
            written for, since a prompt is what AppKit drops first
            """)
    }

    // MARK: - Collapsed

    /// Forced directly under AppKit's own 160 pt floor, the way
    /// `ASearchFieldSaysWhatItIsTests.Mount.forceCollapsed` forced it — a bare
    /// toolbar with nothing beside the field rests open at any width this
    /// fixture can reach, so reaching the collapsed state honestly needs a
    /// crowded bar this file has no reason to build.
    private func forceCollapsed(_ field: NSSearchField, _ fixture: LivePageToolbarFixture) {
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
            the control's magnifier opens onto a field with no name
            """)
    }

    // MARK: - A page change

    /// A page change here means a different page — one with its own token —
    /// drawn under the *same* `LivePageToolbarFixture`, the same window and
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
        let fixture = LivePageToolbarFixture(SwitchingPage(pageSwitch: pageSwitch, holderA: holderA,
                                                           holderB: holderB),
                                             selection: .module("test.searchPageA"),
                                             width: 1060, height: 500)
        fixtures.append(fixture)
        fixture.settle(25)

        let fieldA = try XCTUnwrap(field(fixture, "page A"))
        XCTAssertEqual(fieldA.accessibilityLabel(), HelmA11y.searchField,
                       "precondition: page A's own field starts unnamed")

        pageSwitch.showsB = true
        fixture.model.selection = .module("test.searchPageB")
        fixture.settle(25)

        let fieldB = try XCTUnwrap(field(fixture, "page B"))
        XCTAssertFalse(fieldA === fieldB, """
            precondition: the same field object came back for a different page, so this case \
            proves nothing about a field built fresh
            """)
        XCTAssertEqual(fieldB.accessibilityLabel(), HelmA11y.searchField, """
            the field built for the second page has no name — a one-off naming would leave \
            every page but the first without one
            """)
    }
}
