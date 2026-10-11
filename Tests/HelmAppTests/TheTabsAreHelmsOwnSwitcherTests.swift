import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **Owner item (0): the tabs have one form.** A dev-only style toggle used
/// to let a dev build choose between AppKit's own `NSToolbarItemGroup` and
/// Helm's `HelmToolbarSwitcher`; retired 2026-09-23 once the owner had looked
/// at both on a real window and kept the Helm one. Every build — dev or not —
/// before this pass read the *native* form by default unless it was both a
/// dev build and had been told otherwise, so a test process, which is never a
/// dev build, always built the group this file asserts is gone.
@MainActor
final class TheTabsAreHelmsOwnSwitcherTests: XCTestCase {

    private func content() -> HelmPageToolbarContent {
        HelmPageToolbarContent(
            tabs: [HelmToolbarTab(id: "a", title: "A", symbol: "circle"),
                   HelmToolbarTab(id: "b", title: "B", symbol: "square")],
            selectedTab: .constant("a"))
    }

    func testTheTabsItemIsHelmsOwnSwitcherAndNotANativeGroup() throws {
        let model = SettingsModel(host: ModuleHost.shared)
        let channel = HelmWindowToolbarChannel()
        let toolbar = SettingsToolbar(model: model, channel: channel)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 700),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        toolbar.window = window

        model.selection = .module("test.pageTabsOnly")
        channel.declare(content(), token: "test.pageTabsOnly", generation: channel.nextGeneration())
        window.layoutIfNeeded()

        let bar = try XCTUnwrap(window.toolbar, "the page never got a toolbar")
        let tabsItem = try XCTUnwrap(
            bar.items.first { $0.itemIdentifier.rawValue == "helm.tabs" },
            "no helm.tabs item in \(bar.items.map(\.itemIdentifier.rawValue))")

        XCTAssertFalse(tabsItem is NSToolbarItemGroup, """
            the tabs item is an NSToolbarItemGroup — the native form the dev toggle used to build \
            by default outside a dev build, which this pass retired
            """)

        let view = try XCTUnwrap(tabsItem.view, "the tabs item carries no custom view at all")
        view.layoutSubtreeIfNeeded()
        let controls = view.everyView(ofType: NSSegmentedControl.self)
        XCTAssertEqual(controls.count, 1, """
            the tabs item's view holds \(controls.count) NSSegmentedControl(s), not exactly one — \
            HelmToolbarSwitcher wraps exactly one
            """)
        _ = toolbar
    }
}
