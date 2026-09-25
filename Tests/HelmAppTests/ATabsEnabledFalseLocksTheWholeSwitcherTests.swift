import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`HelmPageToolbarContent.tabsEnabled` dims the switcher whole — it is not
/// `isInteractive` again under another name.** Uninstaller's own review step
/// is the first caller: the switcher has to read disabled while a person is
/// mid-review, with the rest of the bar (a live Refresh, an open search field)
/// untouched, which is the opposite shape from `AnOrdinaryReturnVisitKeepsTheBarLitTests`,
/// where a *frozen* bar's own `isInteractive` dims everything at once. A page
/// can be fully live and still ask for this — there is no `isLive` anywhere
/// in this file.
@MainActor
final class ATabsEnabledFalseLocksTheWholeSwitcherTests: XCTestCase {

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
        fixture.channel.declare(HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: Binding(get: { selected }, set: { selected = $0 }),
            tabsEnabled: false),
            token: "test.lockedTabs", generation: fixture.channel.nextGeneration())
        fixture.window.layoutIfNeeded()

        let bar = try XCTUnwrap(fixture.window.toolbar, "page never got a toolbar")
        let tabsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" })
        let tabsView = try XCTUnwrap(tabsItem.view)
        let control = try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs item")
        XCTAssertFalse(control.isEnabled, "the switcher still reads enabled with tabsEnabled: false")

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
