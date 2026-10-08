import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Defect found while adding `HelmToolbarAction.Kind`, and fixed in this
/// pass**: the toolbar that held the search field set its accessibility label
/// once, at construction, and the method every later refresh calls, a
/// language change among them, never set it again. Nothing about the
/// field's shape moves on a language change, so nothing else would have
/// rebuilt it either. The deleted `ASearchFieldSaysWhatItIsTests` proved the
/// same shape of defect for the SwiftUI-bridge-era field (`ToolbarSearchName`,
/// also deleted); this is its twin for the field the page bar's search zone
/// (`ShellBarSearch`) builds directly, through a mounted bar and the channel,
/// rather than mounting a page.
@MainActor
final class TheSearchFieldsNameFollowsALanguageChangeThroughTheNewToolbarTests: XCTestCase {

    private struct Fixture {
        let pageBar: MountedPageBar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var fixtures: [Fixture] = []

    /// The bar reads these when it is built, so they are pinned before one is and put back after.
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
        fixtures.forEach { $0.pageBar.remove() }
        fixtures = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        super.tearDown()
    }

    private func makeBar() -> Fixture {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let fixture = Fixture(pageBar: MountedPageBar(model: model, channel: channel, in: window),
                              model: model, channel: channel, window: window)
        fixtures.append(fixture)
        return fixture
    }

    /// The search field the bar in the window holds, found by a walk down from the window's frame view
    /// and held to be the mounted bar's own search zone.
    private func searchField(_ fixture: Fixture) throws -> NSSearchField {
        let found = fixture.window.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        XCTAssertTrue(found === fixture.pageBar.bar.view, "the bar in the window is not the mounted bar")
        let zone = try XCTUnwrap(found?.view(for: .search), "page never got a search zone")
        XCTAssertTrue(zone === fixture.pageBar.search.view, "the search zone is not the mounted bar's own")
        return try XCTUnwrap(zone.everyView(ofType: NSSearchField.self).first, "no search field in the zone")
    }

    /// A name that is neither the app's own word for the field nor nil, so
    /// «nothing happened» and «it was re-read» are two different readings
    /// rather than one — the same device the deleted ancestor of this file
    /// (`ASearchFieldSaysWhatItIsTests`) planted before posting the notice.
    func testALanguageChangeReReadsTheSearchFieldsAccessibilityLabel() throws {
        let fixture = makeBar()
        fixture.model.selection = .module("test.searchName")
        fixture.channel.declare(HelmPageToolbarContent(
            search: HelmToolbarSearch(prompt: "Search apps", text: .constant(""))
        ), token: "test.searchName", generation: fixture.channel.nextGeneration())
        fixture.pageBar.layout()

        let field = try searchField(fixture)

        field.setAccessibilityLabel("a name from the language before")
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        fixture.pageBar.layout()

        XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField, """
            the app changed language and the field kept \
            «\(field.accessibilityLabel() ?? "no name at all")» — the search zone does not re-read \
            the field's own accessibility label on a language change
            """)
    }

    /// **Every language answers**, not only the one this machine happens to
    /// be set to (CLAUDE.md's rule that language assertions go through `EachLanguage.swift`) — one
    /// `.helmLanguageChanged` notice per language, the same route the case
    /// above already proved wired to the search zone, so this one only has to
    /// show the re-read is not a fluke of whichever language the notice
    /// above happened to land in.
    func testTheLabelIsInTodaysLanguageInEveryLanguage() throws {
        let fixture = makeBar()
        fixture.model.selection = .module("test.searchNameLanguages")
        fixture.channel.declare(HelmPageToolbarContent(
            search: HelmToolbarSearch(prompt: "Search apps", text: .constant(""))
        ), token: "test.searchNameLanguages", generation: fixture.channel.nextGeneration())
        fixture.pageBar.layout()

        let field = try searchField(fixture)

        AppLanguage.each { language in
            NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
            fixture.pageBar.layout()
            XCTAssertEqual(field.accessibilityLabel(), HelmA11y.searchField,
                           "\(language.rawValue): the field answers in another language")
        }
    }

    /// **Ported from the deleted `ASearchFieldSaysWhatItIsTests
    /// .testTheNameIsAWordAndNotTheRole`**, which this pass's own removal of
    /// `ToolbarSearchName` left with no home: `HelmA11y.searchField` is not
    /// wired to `ToolbarSearchName` at all, so the case is pure string logic
    /// and needs no fixture. VoiceOver already announces the role — "search
    /// field" — so a label repeating it reads as "search field search
    /// field", which is exactly the mistake `HelmA11y.searchField`'s own doc
    /// comment says the word "Search" alone was chosen to avoid.
    func testTheNameIsAWordAndNotTheRole() {
        AppLanguage.each { language in
            let name = HelmA11y.searchField
            XCTAssertFalse(name.isEmpty, "\(language.rawValue): the search field's name is empty")
            XCTAssertFalse(name.lowercased().contains("field"), """
                \(language.rawValue): the name «\(name)» repeats the role VoiceOver already \
                announces
                """)
        }
    }
}
