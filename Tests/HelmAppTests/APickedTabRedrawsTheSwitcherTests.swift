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
/// menu pick never touches the control at all, so nothing but a fresh
/// `HelmTabsSnapshot` was ever going to move the one visible segment or its
/// menu's own tick — and a snapshot that left the selection out of its own
/// equality never told `SettingsToolbar.patchTabs` a redeclare carrying a
/// changed `selectedTab` was worth rebuilding for, as long as the ids,
/// titles, symbols, style, interactivity and fold state all stayed the same.
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

    func testARedeclaredSelectionWithNoOtherShapeChangeMovesTheControl() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window

        model.selection = .module("test.picked")
        channel.declare(content(selected: "a"), token: "test.picked", generation: channel.nextGeneration())
        window.layoutIfNeeded()

        let bar = try XCTUnwrap(window.toolbar)
        let tabsItem = try XCTUnwrap(bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" })
        let tabsView = try XCTUnwrap(tabsItem.view)
        let control = try XCTUnwrap(tabsView.everyView(ofType: NSSegmentedControl.self).first,
                                    "no NSSegmentedControl under the tabs item")
        XCTAssertEqual(control.label(forSegment: control.selectedSegment), "A")

        // Nothing about the shape moves here — same ids, titles, symbols,
        // style and fold state — only `selectedTab`, exactly what a menu
        // pick's own write does through the same binding.
        channel.declare(content(selected: "b"), token: "test.picked", generation: channel.nextGeneration())
        window.layoutIfNeeded()

        XCTAssertEqual(control.label(forSegment: control.selectedSegment), "B", """
            the switcher kept showing the tab that was left — a redeclared selection with no \
            other shape change never reached the hosted control
            """)
        _ = toolbar
    }
}
