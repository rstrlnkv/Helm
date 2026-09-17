import AppKit
import HelmTestSupport
import XCTest
@testable import HelmUI

/// **The switcher's own menu.**
///
/// It is the segmented control's `menu`, which is the one place a right-click
/// is answered at all: SwiftUI's `.contextMenu` on a toolbar item opens
/// nothing, and a menu set on the views around a SwiftUI item is ignored,
/// because AppKit builds the bar's own — the display-mode menu, which
/// `SettingsWindow` turns off, since it changed nothing here but the height of
/// the bar.
@MainActor
final class TheSwitcherMenuOffersEveryLabelStyleTests: XCTestCase {

    private func menu(current: ToolbarSwitcherStyle) -> NSMenu {
        HelmToolbarSwitcher<Int>.menu(title: "Tab labels", style: current, target: nil)
    }

    func testEveryStyleIsOfferedOnce() {
        XCTAssertEqual(menu(current: .text).items.map(\.title),
                       ToolbarSwitcherStyle.allCases.map(\.label),
                       "the menu does not offer each label style exactly once, in order")
    }

    func testTheCurrentStyleIsTheTickedOne() {
        for style in ToolbarSwitcherStyle.allCases {
            let ticked = menu(current: style).items.filter { $0.state == .on }.map(\.title)
            XCTAssertEqual(ticked, [style.label], """
                with \(style) chosen the menu ticks \(ticked) — a menu that ticks the wrong item, \
                or none, says nothing about what the bar is showing
                """)
        }
    }

    /// A menu of four titles that carry nothing changes nothing.
    func testEveryItemCarriesItsStyleAndAnAction() {
        for (item, style) in zip(menu(current: .icons).items, ToolbarSwitcherStyle.allCases) {
            XCTAssertEqual(item.representedObject as? String, style.rawValue,
                           "«\(item.title)» does not carry the style it shows")
            XCTAssertNotNil(item.action, "«\(item.title)» sends nothing")
        }
    }
}
