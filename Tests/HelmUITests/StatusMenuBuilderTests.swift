import XCTest
import AppKit
@testable import HelmUI

/// The status menu: every row carries its glyph, and the groups are separated.
///
/// Written because the glyphs were missing on screen while the code that sets
/// them looked right, and "it looks right" is not a way to tell.
@MainActor
final class StatusMenuBuilderTests: XCTestCase {

    private func entry(_ id: String, _ symbol: String) -> StatusMenuBuilder.Entry {
        StatusMenuBuilder.Entry(id: id, title: id.capitalized, symbol: symbol)
    }

    private func build(_ groups: [[StatusMenuBuilder.Entry]]) -> NSMenu {
        StatusMenuBuilder.menu(
            settingsTitle: "Settings…", quitTitle: "Quit",
            groups: groups.map(StatusMenuBuilder.Group.init(entries:)),
            target: nil,
            openSettings: #selector(NSApplication.terminate(_:)),
            openModule: #selector(NSApplication.terminate(_:)),
            quit: #selector(NSApplication.terminate(_:)))
    }

    func testEverySelectableRowHasAGlyph() {
        let menu = build([[entry("disk", "chart.pie"), entry("keyboard", "keyboard")],
                          [entry("vpn", "lock.shield")]])
        let rows = menu.items.filter { !$0.isSeparatorItem }
        XCTAssertEqual(rows.count, 5, "settings, two modules, one module, quit")
        for row in rows {
            XCTAssertNotNil(row.image, "\(row.title) has no glyph")
            XCTAssertTrue(row.image?.isTemplate == true,
                          "\(row.title) must tint with the row, including when highlighted")
        }
    }

    /// A rule before each run of modules and one before Quit — and never two
    /// in a row, which is what an empty category would have produced.
    func testGroupsAreSeparatedAndEmptyOnesLeaveNoGap() {
        let menu = build([[entry("disk", "chart.pie")], [], [entry("vpn", "lock.shield")]])
        let kinds = menu.items.map { $0.isSeparatorItem }
        XCTAssertEqual(kinds, [false, true, false, true, false, true, false],
                       "settings | disk | vpn | quit")
    }

    func testTheModuleIdTravelsWithItsRow() {
        let menu = build([[entry("autopilot", "location.north.circle")]])
        let row = menu.items.first { $0.title == "Autopilot" }
        XCTAssertEqual(row?.representedObject as? String, "autopilot")
    }

    /// Glyphs are sized so the column of them is even; an unsized symbol comes
    /// back at whatever the catalogue says, which differs per symbol.
    func testGlyphsAreAllTheSameSize() {
        let menu = build([[entry("disk", "chart.pie"), entry("keyboard", "keyboard")]])
        for row in menu.items where !row.isSeparatorItem {
            XCTAssertEqual(row.image?.size, StatusMenuBuilder.glyphSize, row.title)
        }
    }

    func testNoModulesLeavesSettingsAndQuitWithOneRuleBetween() {
        let menu = build([[], []])
        XCTAssertEqual(menu.items.map(\.isSeparatorItem), [false, true, false])
    }
}
