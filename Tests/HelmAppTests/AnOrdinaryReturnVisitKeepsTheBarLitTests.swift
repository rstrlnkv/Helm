import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Owner item (3): no text animation in the tabs on an ordinary return
/// visit.** AppKit's own eviction-and-reinsertion fade is one cause, closed
/// by keeping the tabs in the bar throughout a return visit rather than
/// letting them overflow (see `SettingsToolbar`'s folding mechanism); this
/// file exists for a *second* rebuild that stayed even once the tabs never
/// left the bar: `freeze(_:)` used to disable every control unconditionally, driving
/// `HelmTabsSnapshot`'s `isLive` from `true` to `false` and back to `true`
/// the instant the page redeclared, which is a disabled-then-enabled flip on
/// the tabs' own text with nothing in between for a person to read as
/// intentional. `freeze(_:visibly:)` now takes that flip only when the page
/// is *not* expected back this turn (`SettingsToolbar.swift`'s own header on
/// `isReturnVisit`); an ordinary return visit — select A, leave for B,
/// return to A before A has had a chance to redeclare — must show the tabs,
/// the actions capsule and the search field exactly as interactive as they
/// were, the whole time.
@MainActor
final class AnOrdinaryReturnVisitKeepsTheBarLitTests: XCTestCase {

    private func content(selected: String) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: .constant(selected),
            actions: [HelmToolbarAction(id: "act", title: "Act", symbol: "bolt") {}],
            search: HelmToolbarSearch(prompt: "Search", text: .constant("")))
    }

    /// Declare A, select B, declare B, withdraw A (A's own generation), select
    /// A again — before A has redeclared anything. This is the exact
    /// sequence `SettingsToolbar`'s own header calls "an ordinary return
    /// visit": A was live a moment ago (`wasLive`), and the selection is
    /// switching back to it (`didSwitchPage`), so `freeze(_:visibly:)` must
    /// take the invisible branch.
    func testAnOrdinaryReturnVisitNeverDimsAnything() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window

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
        window.layoutIfNeeded()

        let bar = try XCTUnwrap(window.toolbar, "page A never got a toolbar back")
        let tabsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" })
        let tabsView = try XCTUnwrap(tabsItem.view)
        let control = try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs item")
        XCTAssertTrue(control.isEnabled, """
            the tabs read disabled on an ordinary return visit — freeze(_:visibly:) took the \
            visible branch where the grace period already covers this turn
            """)

        let actionsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.actions" })
        let actionsView = try XCTUnwrap(actionsItem.view as? NSHostingView<HelmToolbarActionsCapsule>,
                                        "the actions item is not hosting HelmToolbarActionsCapsule")
        XCTAssertTrue(actionsView.rootView.model.isInteractive, """
            the actions capsule reads non-interactive on an ordinary return visit
            """)

        let searchItem = try XCTUnwrap(bar.items.compactMap { $0 as? NSSearchToolbarItem }.first)
        XCTAssertTrue(searchItem.searchField.isEnabled, """
            the search field reads disabled on an ordinary return visit
            """)
        _ = toolbar
    }

    /// **A second frozen refresh inside the same grace window must not dim
    /// what the first one already left lit.** `wasLive` alone answers only
    /// for the *first* frozen call after a page stops declaring — a second
    /// one lands with `wasLive` already `false` (the first freeze cleared
    /// it), and a language, page-bar or switcher-style change calls
    /// `refresh()` unconditionally, whether or not a page switch is under
    /// way (`refreshAndResettle()`). Without keying `isReturnVisit` on the
    /// grace period actually being armed for this page, that second call
    /// dimmed the tabs, the actions capsule and the search field a moment
    /// after the first one had shown them lit, and the redeclare a moment
    /// later lit them again — the disabled-then-enabled flip this whole
    /// mechanism exists to remove.
    func testALanguageChangeDuringGraceDoesNotDimTheBar() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window

        model.selection = .module("test.pageA")
        let genA = channel.nextGeneration()
        channel.declare(content(selected: "a"), token: "test.pageA", generation: genA)

        model.selection = .module("test.pageB")
        channel.declare(content(selected: "a"), token: "test.pageB", generation: channel.nextGeneration())
        channel.withdraw(token: "test.pageA", generation: genA)

        model.selection = .module("test.pageA")
        window.layoutIfNeeded()

        // A second, non-selection refresh lands inside the same grace
        // window — the shape a language, page-bar or switcher-style change
        // takes — before page A has redeclared anything.
        NotificationCenter.default.post(name: .helmLanguageChanged, object: nil)
        window.layoutIfNeeded()

        let bar = try XCTUnwrap(window.toolbar, "page A never got a toolbar back")
        let tabsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" })
        let tabsView = try XCTUnwrap(tabsItem.view)
        let control = try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs item")
        XCTAssertTrue(control.isEnabled, """
            the tabs read disabled after a language change landed inside the same grace window \
            as an ordinary return visit
            """)

        let actionsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.actions" })
        let actionsView = try XCTUnwrap(actionsItem.view as? NSHostingView<HelmToolbarActionsCapsule>,
                                        "the actions item is not hosting HelmToolbarActionsCapsule")
        XCTAssertTrue(actionsView.rootView.model.isInteractive, """
            the actions capsule reads non-interactive after a language change landed inside the \
            same grace window as an ordinary return visit
            """)
        _ = toolbar
    }
}
