import AppKit
import SwiftUI
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Owner item (2): a chosen tab has to reach the hosted switcher, not only
/// the page's own binding.** `HelmToolbarSwitcher.Coordinator.pickedFromMenu`
/// — the compact capsule's own menu — writes straight through the page's
/// `selectedTab` binding, the way a plain click on a full-width segment does
/// too. A plain click also moves AppKit's own `NSSegmentedControl.selected-
/// Segment` directly, as part of its own mouse tracking, which is what
/// masked this defect in the switcher's full form: the control already
/// *looks* right by the time anything SwiftUI-side would have caught up. A
/// menu pick never touches the control at all, so nothing but a redraw from a
/// fresh declaration was ever going to move the one visible segment or its
/// menu's own tick — and in the earlier toolbar, `SettingsToolbar`, the
/// snapshot the tabs were compared by (`HelmTabsSnapshot`) left the selection
/// out of its own equality, so a redeclare carrying a changed `selectedTab`
/// was never worth rebuilding for, as long as the ids, titles, symbols, style,
/// interactivity and fold state all stayed the same. The page bar's tabs zone
/// compares `ShellBarTabs.Drawn`, whose `Shape.selectedID` is the selection.
///
/// This test never needs to fold the tabs or drive AppKit's own menu
/// tracking to see the defect: redeclaring with a different `selectedTab`
/// and nothing else about the shape moving is enough, because the control's
/// own state is not being written to at all in either case — only the page's
/// binding is, which is exactly what a menu pick does.
@MainActor
final class APickedTabRedrawsTheSwitcherTests: XCTestCase {

    private func content(selected: String) -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: .constant(selected),
            actions: [],
            search: nil)
    }

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

    func testARedeclaredSelectionWithNoOtherShapeChangeMovesTheControl() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let mounted = MountedPageBar(model: model, channel: channel, in: window)
        pageBar = mounted

        model.selection = .module("test.picked")
        channel.declare(content(selected: "a"), token: "test.picked", generation: channel.nextGeneration())
        mounted.layout()

        let found = window.contentView?.superview?.everyView(ofType: ShellPageBarView.self).first
        let tabsView = try XCTUnwrap(found?.view(for: .tabs), "the bar in the window holds no tabs zone")
        XCTAssertTrue(found === mounted.bar.view, "the bar in the window is not the mounted bar")
        XCTAssertTrue(tabsView === mounted.tabs.view, "the tabs zone is not the mounted bar's own")
        let control = try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs zone")
        XCTAssertEqual(control.segmentCount, 2, "precondition: the switcher is folded or has other tabs")
        XCTAssertEqual(control.label(forSegment: control.selectedSegment), "A")

        // Nothing about the shape moves here — same ids, titles, symbols,
        // style and fold state — only `selectedTab`, exactly what a menu
        // pick's own write does through the same binding.
        channel.declare(content(selected: "b"), token: "test.picked", generation: channel.nextGeneration())
        mounted.layout()

        XCTAssertEqual(control.label(forSegment: control.selectedSegment), "B", """
            the switcher kept showing the tab that was left — a redeclared selection with no \
            other shape change never reached the hosted control
            """)
    }
}
