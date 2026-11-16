import AppKit
import HelmRuntime
import HelmUI
import SwiftUI
import HelmAppStrings
import XCTest
@testable import HelmApp

/// **The header row's right-click menu offers the right items and each one writes its setting.**
/// A SwiftUI `.contextMenu` on the row never opened for a person (the row is in the title bar zone) and wrote
/// nothing through accessibility; the menu is an `NSMenu` now, so its items and the press that opens it are
/// plain values to read.
@MainActor
final class TheHeaderBarMenuTests: XCTestCase {
    private let band = NSRect(x: 200, y: 700, width: 900, height: 52)

    private func open(_ type: NSEvent.EventType, _ modifiers: NSEvent.ModifierFlags = [], at point: NSPoint,
                      excluding: [NSRect] = []) -> Bool {
        HeaderBarMenu.opens(type: type, modifiers: modifiers, at: point, band: band, excluding: excluding)
    }

    func testTheGestureIsARightPressOrAControlledLeftOneInsideTheBand() {
        let inside = NSPoint(x: 500, y: 720)
        XCTAssertTrue(open(.rightMouseDown, at: inside))
        XCTAssertTrue(open(.leftMouseDown, .control, at: inside))
        XCTAssertFalse(open(.leftMouseDown, at: inside), "a plain left press is a click")
        XCTAssertFalse(open(.rightMouseUp, at: inside))
        XCTAssertFalse(open(.rightMouseDown, at: NSPoint(x: 500, y: 600)), "below the row is the page")
        XCTAssertFalse(open(.rightMouseDown, at: NSPoint(x: 100, y: 720)), "left of the card is the sidebar")
    }

    func testWhatKeepsItsOwnPressIsExcluded() {
        let field = NSRect(x: 800, y: 710, width: 280, height: 32)
        XCTAssertFalse(open(.rightMouseDown, at: NSPoint(x: 900, y: 720), excluding: [field]))
        XCTAssertTrue(open(.rightMouseDown, at: NSPoint(x: 600, y: 720), excluding: [field]))
    }

    private func titles(_ items: [NSMenuItem]) -> [String] { items.map { $0.isSeparatorItem ? "-" : $0.title } }

    func testTabLabelsArePresentOnlyWhereThePageHasTabs() {
        let app = AppSettings.store.over(InMemoryKeyValueStore())
        let with = HeaderBarMenu.items(hasTabs: true, in: app)
        let without = HeaderBarMenu.items(hasTabs: false, in: app)
        XCTAssertEqual(with.count, 12)
        XCTAssertEqual(without.count, 7)
        XCTAssertTrue(titles(with).contains(AppStr.tabLabels))
        XCTAssertFalse(titles(without).contains(AppStr.tabLabels))
        XCTAssertFalse(without.contains { $0.action == nil && !$0.isSeparatorItem && $0.title == "" })
    }

    func testTheTickIsTheStoredChoiceAndEachItemWritesItsSetting() {
        let app = AppSettings.store.over(InMemoryKeyValueStore())
        func item(_ title: String, tabs: Bool = true) -> NSMenuItem {
            HeaderBarMenu.items(hasTabs: tabs, in: app).first { $0.title == title && $0.action != nil }!
        }
        func ticked(_ title: String) -> Bool { item(title).state == .on }
        XCTAssertTrue(ticked(AppStr.pageBarWithIcon))
        XCTAssertFalse(ticked(AppStr.pageBarWithoutIcon))
        XCTAssertTrue(ticked(AppStr.tabLabelsText))
        XCTAssertTrue(ticked(AppStr.barAppearanceFlat))

        func choose(_ item: NSMenuItem) { _ = item.target?.perform(item.action, with: item) }
        choose(item(AppStr.pageBarWithoutIcon))
        choose(item(AppStr.tabLabelsIcons))
        choose(item(AppStr.barAppearanceLiquidGlass))
        XCTAssertEqual(AppSettings.pageBarStyle(in: app), .windowTitle)
        XCTAssertEqual(AppSettings.toolbarSwitcherStyle(in: app), .icons)
        XCTAssertEqual(AppSettings.barAppearance(in: app), .liquidGlass)
        XCTAssertTrue(ticked(AppStr.pageBarWithoutIcon))
        XCTAssertFalse(ticked(AppStr.pageBarWithIcon))
        XCTAssertTrue(ticked(AppStr.tabLabelsIcons))
        XCTAssertTrue(ticked(AppStr.barAppearanceLiquidGlass))
    }

    /// The menu's has-tabs fact is what the page on screen declared for the row, not a guess from the selection:
    /// a module page with tabs (Homebrew's) has them, the same selection with none declared has none.
    func testTheHasTabsFactIsTheDeclaredContentNotTheSelection() {
        let model = SettingsModel(host: .shared)
        model.selection = .module("homebrew")
        let tab = HelmToolbarTab(id: "a", title: "A", symbol: "tray")
        func hosted(_ content: HelmPageToolbarContent?) -> Bool {
            let view = Color.clear.helmWindowToolbar(content).mirrorsHeaderTabs(into: model)
            let host = NSHostingView(rootView: view.frame(width: 200, height: 100))
            host.frame = NSRect(x: 0, y: 0, width: 200, height: 100)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            return model.pageHasTabs
        }
        XCTAssertTrue(hosted(HelmPageToolbarContent(tabs: [tab], selectedTab: .constant("a"))))
        XCTAssertFalse(hosted(HelmPageToolbarContent(tabs: [])), "Leftovers with an empty list declares none")
        XCTAssertFalse(hosted(nil))
    }
}
