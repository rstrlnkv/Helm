import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Owner item (3): no text animation in the tabs on an ordinary return
/// visit.** AppKit's own eviction-and-reinsertion fade is one cause, closed
/// by keeping the tabs in the bar throughout a return visit rather than
/// letting them overflow (the bar's tabs fold by the layout's verdict); this
/// file exists for a *second* rebuild that stayed even once the tabs never
/// left the bar: a freeze used to disable every control unconditionally, driving
/// the tabs' `isLive` from `true` to `false` and back to `true`
/// the instant the page redeclared, which is a disabled-then-enabled flip on
/// the tabs' own text with nothing in between for a person to read as
/// intentional. the bar's freeze now takes that flip only when the page
/// is *not* expected back this turn (`ShellPageBar`'s `isReturnVisit`); an ordinary return visit — select A, leave for B,
/// return to A before A has had a chance to redeclare — must show the tabs,
/// the actions capsule and the search field exactly as interactive as they
/// were, the whole time.
@MainActor
final class AnOrdinaryReturnVisitKeepsTheBarLitTests: XCTestCase {

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var savedLabelStyle: Any?
    private var pageBar: MountedPageBar?

    /// The bar reads these when it is built (its tabs zone reads the label style when it shows), so they
    /// are pinned before one is and put back after.
    override func setUp() {
        super.setUp()
        savedCollapse = AppSettings.store.object("alwaysCollapseSearch")
        savedPageBar = AppSettings.store.object(PageBarStyle.storageKey)
        savedBarAppearance = AppSettings.store.object(HelmBarAppearance.storageKey)
        savedLabelStyle = AppSettings.store.object(ToolbarSwitcherStyle.storageKey)
        AppSettings.pageBarStyle = .windowTitle
        AppSettings.barAppearance = .flat
        AppSettings.alwaysCollapseSearch = false
        AppSettings.toolbarSwitcherStyle = .text
    }

    override func tearDown() {
        pageBar?.remove()
        pageBar = nil
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        AppSettings.store.set(savedLabelStyle, for: ToolbarSwitcherStyle.storageKey)
        super.tearDown()
    }

    /// The tabs, the actions capsule and the search field of the bar in the window, read off the zones
    /// found by a walk down from the window's frame view and held to be the mounted bar's own. The page
    /// is frozen (`isLive` false) and not dimmed: a bar that never reached that state read lit for no
    /// reason this file cares about.
    private func assertLit(_ mounted: MountedPageBar, _ window: NSWindow, after what: String) throws {
        let found = window.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        XCTAssertTrue(found === mounted.bar.view, "the bar in the window is not the mounted bar")
        XCTAssertEqual(mounted.bar.presentation, .page(key: "test.pageA", isLive: false, isDimmed: false),
                       "precondition: page A is shown frozen and lit, not dimmed and not fallen to the name")

        let tabsView = try XCTUnwrap(found?.view(for: .tabs), "page A never got its tabs back")
        XCTAssertTrue(tabsView === mounted.tabs.view, "the tabs zone is not the mounted bar's own")
        let control = try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs zone")
        XCTAssertTrue(control.isEnabled, "the tabs read disabled after \(what)")

        XCTAssertNotNil(found?.view(for: .actions), "page A never got its actions back")
        XCTAssertTrue(mounted.actions.model.isInteractive,
                      "the actions capsule reads non-interactive after \(what)")

        let searchView = try XCTUnwrap(found?.view(for: .search), "page A never got its search back")
        let field = try XCTUnwrap(searchView.everyView(ofType: NSSearchField.self).first,
                                  "no NSSearchField under the search zone")
        XCTAssertTrue(field.isEnabled, "the search field reads disabled after \(what)")
    }

    private func content(selected: String) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: .constant(selected),
            actions: [HelmToolbarAction(id: "act", title: "Act", symbol: "bolt") {}],
            search: HelmToolbarSearch(prompt: "Search", text: .constant("")))
    }

    /// Declare A, select B, declare B, withdraw A (A's own generation), select
    /// A again — before A has redeclared anything. This is the return visit
    /// `ShellPageBar.refresh` reads as `isReturnVisit`: A was live a moment ago
    /// (`wasLive`), and the selection is switching back to it (`didSwitch`), so
    /// the freeze must take the branch that does not dim.
    func testAnOrdinaryReturnVisitNeverDimsAnything() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let mounted = MountedPageBar(model: model, channel: channel, in: window)
        pageBar = mounted

        model.selection = .module("test.pageA")
        let genA = channel.nextGeneration()
        channel.declare(content(selected: "a"), token: "test.pageA", generation: genA)

        model.selection = .module("test.pageB")
        channel.declare(content(selected: "a"), token: "test.pageB", generation: channel.nextGeneration())

        // A's own subtree tears down — the ordinary shape of leaving a page,
        // per `HelmWindowToolbar.swift`'s own header on `dismantleNSView`.
        channel.withdraw(token: "test.pageA", generation: genA)

        // Return to A before it has redeclared anything.
        model.selection = .module("test.pageA")
        mounted.layout()

        try assertLit(mounted, window, after: "an ordinary return visit")
    }

    /// **A second frozen refresh inside the same grace window must not dim
    /// what the first one already left lit.** `wasLive` alone answers only
    /// for the *first* frozen pass after a page stops declaring — a second
    /// one lands with `wasLive` already `false` (the first freeze cleared
    /// it), and a language or setting change reaches `ShellPageBar.refresh`
    /// whether or not a page switch is under way (`heard`). Without keying
    /// `isReturnVisit` on a grace being armed for this page (`graceArmed`),
    /// that second pass dimmed the tabs, the actions capsule and the search
    /// field a moment after the first one had shown them lit, and the
    /// redeclare a moment later lit them again — the disabled-then-enabled
    /// flip this whole mechanism exists to remove.
    func testALanguageChangeDuringGraceDoesNotDimTheBar() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let mounted = MountedPageBar(model: model, channel: channel, in: window)
        pageBar = mounted

        model.selection = .module("test.pageA")
        let genA = channel.nextGeneration()
        channel.declare(content(selected: "a"), token: "test.pageA", generation: genA)

        model.selection = .module("test.pageB")
        channel.declare(content(selected: "a"), token: "test.pageB", generation: channel.nextGeneration())
        channel.withdraw(token: "test.pageA", generation: genA)

        model.selection = .module("test.pageA")
        mounted.layout()

        // A second, non-selection refresh lands inside the same grace
        // window — the shape a language, page-bar or switcher-style change
        // takes — before page A has redeclared anything.
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        mounted.layout()

        try assertLit(mounted, window, after: "a language change landed inside the same grace window as an ordinary return visit")
    }
}
