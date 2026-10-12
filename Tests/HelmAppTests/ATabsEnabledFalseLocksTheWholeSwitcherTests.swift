import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`HelmPageToolbarContent.tabsEnabled` dims the switcher whole — it is not
/// `isInteractive` again under another name.** Uninstaller's own review step
/// is the first caller: the switcher has to read disabled while a person is
/// mid-review, with the rest of the bar (a live Refresh, an enabled search
/// field) untouched — the row reads both from the toolbar — which is the
/// opposite shape from `AnOrdinaryReturnVisitKeepsTheBarLitTests`, where a
/// *frozen* bar's own `isInteractive` dims everything at once. A page can be
/// fully live and still ask for this — there is no `isLive` anywhere in this
/// file.
///
/// **The bar.** A `SettingsToolbar` built with the default lead
/// `.sidebarSeparator` on a bare `NSWindow`, not the `lead: .spacer` bar the
/// app's window builds: it has no `helm.tabsLead` and no capped search field.
///
/// **The subject comes first**: the same page is declared with its tabs
/// enabled, the control is read enabled, and only then is the lock declared,
/// so a control that was never enabled (a bar nobody declared on) cannot pass
/// for a locked one. The row is pinned to Flat and not run under Liquid Glass:
/// the settings are pinned in `setUp` (`PinnedBarSettings`), because another
/// run shares the test tool's defaults domain and the bar reads its look when
/// it is built.
@MainActor
final class ATabsEnabledFalseLocksTheWholeSwitcherTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        PinnedBarSettings.pin(in: self)
    }

    private struct Fixture {
        let toolbar: SettingsToolbar
        let model: SettingsModel
        let channel: HelmWindowToolbarChannel
        let window: NSWindow
    }

    private func makeToolbar() -> Fixture {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window
        return Fixture(toolbar: toolbar, model: model, channel: channel, window: window)
    }

    /// The hosted `NSSegmentedControl` reads disabled, every item in the
    /// tabs item's own overflow menu reads disabled, and a pick through that
    /// menu — the only route left to reach a disabled control at all, since
    /// AppKit itself refuses to send an action for a disabled view — leaves
    /// the page's own `selectedTab` binding untouched. Mutation: drop the
    /// `|| !(bar.content?.tabsEnabled ?? true)` half of `helmSwitcherView`'s
    /// `.disabled(...)`, or the `content.tabsEnabled` half of
    /// `patchTabsMenu`'s `menuItem.isEnabled`, or the `bar.content?
    /// .tabsEnabled ?? true` guard in `tabsMenuItemPressed` — each on its own
    /// must turn a piece of this red.
    func testTabsEnabledFalseDisablesTheSwitcherItsMenuAndAPickThroughIt() throws {
        let fixture = makeToolbar()
        var selected = "a"
        fixture.model.selection = .module("test.lockedTabs")
        func declare(tabsEnabled: Bool) {
            fixture.channel.declare(HelmPageToolbarContent(
                tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                       HelmToolbarTab(id: "b", title: "B", symbol: "square")],
                selectedTab: Binding(get: { selected }, set: { selected = $0 }),
                tabsEnabled: tabsEnabled,
                actions: [HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}],
                search: HelmToolbarSearch(prompt: "Search", text: .constant(""))),
                token: "test.lockedTabs", generation: fixture.channel.nextGeneration())
            fixture.window.layoutIfNeeded()
        }
        func tabsControl() throws -> (item: NSToolbarItem, control: NSSegmentedControl) {
            let bar = try XCTUnwrap(fixture.window.toolbar, "page never got a toolbar")
            let tabsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" })
            let tabsView = try XCTUnwrap(tabsItem.view)
            return (tabsItem, try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                            "no NSSegmentedControl under the tabs item"))
        }

        // The subject: the same page, tabs enabled, takes presses.
        declare(tabsEnabled: true)
        XCTAssertTrue(try tabsControl().control.isEnabled, """
            precondition: the switcher reads disabled before the lock — nothing below says the lock did it
            """)

        declare(tabsEnabled: false)
        let (tabsItem, control) = try tabsControl()
        XCTAssertFalse(control.isEnabled, "the switcher still reads enabled with tabsEnabled: false")

        // The rest of the bar stays lit: the Refresh beside the tabs and the search field.
        let bar = try XCTUnwrap(fixture.window.toolbar, "page never got a toolbar")
        let capsule = try ActionsCapsuleReading.read(bar, context: "tabsEnabled: false").capsule
        XCTAssertTrue(capsule.model.isInteractive, "locking the tabs dimmed the actions capsule with them")
        let searchItem = try XCTUnwrap(bar.items.compactMap { $0 as? NSSearchToolbarItem }.first,
                                       "no search item on the toolbar")
        XCTAssertTrue(searchItem.searchField.isEnabled, "locking the tabs disabled the search field with them")

        let submenu = try XCTUnwrap(tabsItem.menuFormRepresentation?.submenu,
                                    "the tabs item's own overflow menu form is missing")
        XCTAssertFalse(submenu.items.isEmpty, "precondition: nothing in the tabs menu to check")
        for item in submenu.items {
            XCTAssertFalse(item.isEnabled, """
                «\(item.title)»: a locked switcher's own overflow menu item is still enabled
                """)
        }

        let bItem = try XCTUnwrap(submenu.items.first { $0.representedObject as? String == "b" })
        if let action = bItem.action { _ = bItem.target?.perform(action, with: bItem) }
        XCTAssertEqual(selected, "a", """
            a pick through a locked switcher's own overflow menu moved the selection anyway — \
            tabsMenuItemPressed did not refuse it
            """)
        _ = fixture.toolbar
    }
}
