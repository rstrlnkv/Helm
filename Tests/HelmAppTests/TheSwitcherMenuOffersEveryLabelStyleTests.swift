import AppKit
import HelmTestSupport
import XCTest
@testable import HelmApp
@testable import HelmUI

/// **The tabs' label style, as the bar's own right-click menu offers it.**
///
/// It used to be the switcher's own menu; the owner's toolbar menu
/// (2026-09-27) folded it into one menu for the whole bar
/// (`SettingsToolbar.barMenuItems`), where it is the "Tab labels" section on a
/// page that has tabs. What it must still do is what it did: offer every style
/// once, tick the current one, and carry the style each item stands for.
@MainActor
final class TheSwitcherMenuOffersEveryLabelStyleTests: XCTestCase {

    /// The items under the "Tab labels" header, up to the next separator.
    private func section(current: ToolbarSwitcherStyle) -> [NSMenuItem] {
        let items = SettingsToolbar.barMenuItems(pageBarStyle: .moduleName, tabLabels: current,
                                                 alwaysCollapseSearch: nil, target: nil)
        guard let header = items.firstIndex(where: { $0.isSectionHeader && $0.title == AppStr.tabLabels })
        else { return [] }
        return Array(items[(header + 1)...].prefix { !$0.isSeparatorItem && !$0.isSectionHeader })
    }

    func testEveryStyleIsOfferedOnce() {
        XCTAssertEqual(section(current: .text).map(\.title),
                       ToolbarSwitcherStyle.allCases.map(\.label),
                       "the menu does not offer each label style exactly once, in order")
    }

    func testTheCurrentStyleIsTheTickedOne() {
        for style in ToolbarSwitcherStyle.allCases {
            let ticked = section(current: style).filter { $0.state == .on }.map(\.title)
            XCTAssertEqual(ticked, [style.label], """
                with \(style) chosen the menu ticks \(ticked) — a menu that ticks the wrong item, \
                or none, says nothing about what the bar is showing
                """)
        }
    }

    /// A menu of titles that carry nothing changes nothing.
    func testEveryItemCarriesItsStyleAndAnAction() {
        let items = section(current: .icons)
        XCTAssertEqual(items.count, ToolbarSwitcherStyle.allCases.count, "no Tab labels section to read")
        for (item, style) in zip(items, ToolbarSwitcherStyle.allCases) {
            XCTAssertEqual(item.representedObject as? String, style.rawValue,
                           "«\(item.title)» does not carry the style it shows")
            XCTAssertNotNil(item.action, "«\(item.title)» sends nothing")
        }
    }
}
