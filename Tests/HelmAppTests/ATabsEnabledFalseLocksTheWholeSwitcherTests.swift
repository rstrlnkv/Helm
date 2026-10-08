import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **`HelmPageToolbarContent.tabsEnabled` dims the switcher whole — it is not `isInteractive` again under
/// another name.** Uninstaller's own review step is the first caller: the switcher has to read disabled while
/// a person is mid-review, with the rest of the bar (a live Refresh, an open search field) untouched, which
/// is the opposite shape from `AnOrdinaryReturnVisitKeepsTheBarLitTests`, where a *frozen* bar's own
/// `isInteractive` dims everything at once. A page can be fully live and still ask for this — the one
/// `isLive` in this file is the last precondition's reading that the bar shows the page live.
///
/// Read off the page bar's tabs zone in a window (`LivePageToolbarFixture`), unfolded. The folded form is
/// the same switcher drawn compact, with a menu of every tab of its own (`HelmToolbarSwitcher`'s
/// `tabsMenu`): a press raises it only on an enabled control, and a pick from it ends in the same `pick`;
/// this file does not fold the tabs. What the bar's menu (`ShellBarMenu.fill`) offers does not include the
/// tabs. The press that reaches the page's binding is the control's own action, which AppKit itself refuses
/// for a disabled control and which the zone refuses a second time in `pick`; this sends the action by hand,
/// to reach that second refusal.
@MainActor
final class ATabsEnabledFalseLocksTheWholeSwitcherTests: XCTestCase {

    private var savedCollapse: Any?
    private var savedPageBar: Any?
    private var savedBarAppearance: Any?
    private var savedLabelStyle: Any?
    private var fixtures: [LivePageToolbarFixture] = []

    /// The bar reads these when it is built (its tabs zone reads the label style when it shows), so they are
    /// pinned before a fixture is and put back after.
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
        fixtures.forEach { $0.drop() }
        fixtures = []
        AppSettings.store.set(savedCollapse, for: "alwaysCollapseSearch")
        AppSettings.store.set(savedPageBar, for: PageBarStyle.storageKey)
        AppSettings.store.set(savedBarAppearance, for: HelmBarAppearance.storageKey)
        AppSettings.store.set(savedLabelStyle, for: ToolbarSwitcherStyle.storageKey)
        super.tearDown()
    }

    /// The switcher the bar in the window holds, found by a walk of that bar and held to be the fixture's
    /// own tabs zone.
    private func control(_ fx: LivePageToolbarFixture) -> NSSegmentedControl? {
        let found = fx.mount.window?.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        guard let zone = found?.view(for: .tabs), zone === fx.pageBar.tabs.view else { return nil }
        return zone.everyView(ofType: NSSegmentedControl.self).first
    }

    /// The page's own selection, on a class so the binding the bar is handed can write it.
    private final class Selection { var id = "a" }

    /// Declares the two tabs on the fixture's channel, bound to `selection`.
    private func declare(_ fx: LivePageToolbarFixture, _ selection: Selection, tabsEnabled: Bool,
                         actions: [HelmToolbarAction] = []) {
        fx.channel.declare(HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: Binding(get: { selection.id }, set: { selection.id = $0 }),
            tabsEnabled: tabsEnabled,
            actions: actions),
            token: "test.lockedTabs", generation: fx.channel.nextGeneration())
        fx.settle(10)
    }

    /// The hosted `NSSegmentedControl` reads disabled, and a press the control's action carries to the zone
    /// leaves the page's own `selectedTab` binding untouched; the same press on a switcher that is enabled
    /// moves it, so the refusal is not a press that never arrived. A live action beside the locked switcher
    /// stays live. Mutation: drop the `|| !content.tabsEnabled` half of `ShellBarTabs.show`'s `isDisabled`, or
    /// the `content.tabsEnabled` half of `pick`'s guard — each on its own must turn a piece of this red.
    func testTabsEnabledFalseDisablesTheSwitcherAndRefusesAPressOnIt() throws {
        let fx = LivePageToolbarFixture(Color.clear, selection: .module("test.lockedTabs"),
                                        width: 1060, height: 700)
        fixtures.append(fx)
        let selection = Selection()

        // The subject first: an enabled switcher takes the press.
        declare(fx, selection, tabsEnabled: true)
        let open = try XCTUnwrap(control(fx), "the bar in the window holds no tabs switcher")
        XCTAssertEqual(open.segmentCount, 2, "precondition: the switcher is folded or has other tabs")
        XCTAssertTrue(open.isEnabled, "precondition: the switcher reads disabled with tabsEnabled: true")
        open.selectedSegment = 1
        XCTAssertTrue(open.sendAction(open.action, to: open.target), "the control's own action went nowhere")
        XCTAssertEqual(selection.id, "b", "precondition: a press on an enabled switcher did not reach the page")
        selection.id = "a"

        declare(fx, selection, tabsEnabled: false, actions: [
            HelmToolbarAction(id: "refresh", title: "Refresh", symbol: "arrow.clockwise") {}
        ])
        let locked = try XCTUnwrap(control(fx), "the locked switcher is gone from the bar")
        XCTAssertFalse(locked.isEnabled, "the switcher still reads enabled with tabsEnabled: false")
        locked.selectedSegment = 1
        _ = locked.sendAction(locked.action, to: locked.target)
        XCTAssertEqual(selection.id, "a", """
            a press the locked switcher's action carried moved the selection anyway — the zone's pick did \
            not refuse it
            """)

        XCTAssertEqual(fx.bar.presentation, .page(key: "test.lockedTabs", isLive: true, isDimmed: false),
                       "precondition: the bar is not showing the live page")
        XCTAssertTrue(fx.pageBar.actions.model.isInteractive, """
            the page's own action is dimmed with the switcher — tabsEnabled: false is not the bar's whole \
            freeze
            """)
    }
}
