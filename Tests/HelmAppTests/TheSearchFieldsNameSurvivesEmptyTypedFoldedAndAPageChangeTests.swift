import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The page bar's search has an accessibility name in every state a person can meet it in.**
///
/// The search zone (`ShellBarSearch`) holds a field and a magnifier and shows one of them. The field is named
/// when it is empty, when it holds a value, and after a page change; folded, what a person with VoiceOver
/// meets is the magnifier, so the magnifier carries the same name and the hidden field keeps it for the
/// moment the magnifier's press opens it. Today's language and a language notice are held by
/// `TheMagnifierAndTheFieldNameThemselvesInEveryLanguageAfterASecondShow` in `TheSearchRestsAsItsMagnifierTests`.
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

    /// What a page change actually is, for one mounted bar — a
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
        AppSettings.alwaysCollapseSearch = false
    }

    override func tearDown() {
        fixtures.forEach { $0.drop() }
        fixtures = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
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
                \(what): the window holds no search field at all, so there is nothing here \
                whose name could be read — either the page's declare never reached the \
                channel or the bar stopped holding the search zone
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
            the search field is read aloud with no name — the zone set none when the page \
            declared its search
            """)
    }

    // MARK: - With a value

    /// Typed rather than assigned: `controlTextDidChange` is the search zone's
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
            the field has a value and no name — which is the defect this file's ancestor was \
            written for, since a prompt is what AppKit drops first
            """)
    }

    // MARK: - Folded

    /// With `alwaysCollapseSearch` on and the field empty the zone rests as its magnifier: the field is
    /// hidden and the magnifier is the one control a person meets, so it carries the name, and so does the
    /// hidden field that its press opens.
    func testTheFoldedZonesMagnifierHasAName() throws {
        AppSettings.alwaysCollapseSearch = true
        let (fixture, _) = mount(token: "test.searchFolded")
        let field = try XCTUnwrap(field(fixture, "folded"))
        let zone = fixture.pageBar.search
        XCTAssertTrue(field === zone.field, "precondition: the field found in the window is not the zone's")
        XCTAssertTrue(field.isHidden, "precondition: the empty field is not resting as the magnifier")
        XCTAssertFalse(zone.magnifier.isHidden, "precondition: the resting zone shows no magnifier")
        XCTAssertEqual(zone.plate.frame.width, ShellBarLayout.magnifierWidth,
                       "precondition: the plate is not the magnifier's width")

        XCTAssertEqual(zone.magnifier.accessibilityLabel(), HelmA11y.searchField, """
            the zone rests as a magnifier with no name: that is the one control VoiceOver meets
            """)
        // A button is offered to VoiceOver as its cell, so the cell is what the bar's children hold.
        let met = fixture.bar.view.accessibilityChildren() ?? []
        XCTAssertTrue(met.contains { ($0 as? NSCell) === zone.magnifier.cell },
                      "the bar offers VoiceOver no magnifier: the zone's name is on a control nobody meets")
        XCTAssertFalse(met.contains { ($0 as? NSView) === field }, "the bar offers VoiceOver the hidden field")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the hidden field has no name, so the press on the magnifier opens a field with none
            """)

        zone.magnifier.performClick(nil)
        XCTAssertFalse(field.isHidden, "precondition: the magnifier's press did not open the field")
        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField,
                       "the field the magnifier opened has no name")
    }

    // MARK: - A page change

    /// A page change here means a different page — one with its own token — drawn under the *same*
    /// `LivePageToolbarFixture`, the same window and the same bar: switching `pageSwitch.showsB` swaps which
    /// page `SwitchingPage` draws, and `model.selection` moves with it, the way the sidebar's click moves
    /// both. The bar holds one search zone and may keep one field across the change, so a name that is only
    /// kept would pass; both names are taken off before the change, and only a show of page B's declaration
    /// can put them back. Page B's own prompt arriving proves that show happened.
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
        let zone = fixture.pageBar.search
        XCTAssertEqual(fieldA.placeholderString, "Search apps", "precondition: page A's prompt never arrived")
        XCTAssertEqual(fieldA.accessibilityLabel(), HelmA11y.searchField,
                       "precondition: page A's own field starts unnamed")

        fieldA.setAccessibilityLabel(nil)
        zone.magnifier.setAccessibilityLabel(nil)
        XCTAssertNil(fieldA.accessibilityLabel(), "precondition: the field's name was not taken off")
        XCTAssertNil(zone.magnifier.accessibilityLabel(), "precondition: the magnifier's name was not taken off")

        pageSwitch.showsB = true
        fixture.model.selection = .module("test.searchPageB")
        fixture.settle(25)

        let fieldB = try XCTUnwrap(field(fixture, "page B"))
        XCTAssertEqual(fieldB.placeholderString, "Search hosts",
                       "precondition: page B's declaration never reached the zone")
        XCTAssertEqual(fieldB.accessibilityLabel(), HelmA11y.searchField, """
            the field shown for the second page has no name — a one-off naming would leave \
            every page but the first without one
            """)
        XCTAssertEqual(zone.magnifier.accessibilityLabel(), HelmA11y.searchField,
                       "the magnifier shown for the second page has no name")
    }
}
