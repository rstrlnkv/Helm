import AppKit
import HelmTestSupport
import SwiftUI
import XCTest
@testable import HelmApp

/// **While the panel is being arranged, its foot carries «Готово» whatever the
/// three footer switches say.**
///
/// The mode used to have a bar of its own above the footer. Since the Liquid
/// Glass pass (direction B, 2026-09-17) the footer row *is* that bar while the
/// mode is on, and the three switches — Settings, Edit, Quit — are all a person
/// can turn off. A row that hid itself with them would leave a panel in the
/// mode with no way out of it, which is the defect this holds.
///
/// Read as layers of a drawing, because the row is a view and the question is
/// whether it drew: a count of zero is also what an empty window server gives,
/// so the reading row is drawn first and has to draw its rule.
@MainActor
final class TheWayOutOfArrangingIsAlwaysDrawnTests: XCTestCase {

    private func footer(editing: Bool, switchesOn: Bool) -> ModulePageRender.Shell {
        ModulePageRender.drawn(
            PanelFooter(editing: editing, showSettings: switchesOn, showQuit: switchesOn,
                        showEdit: switchesOn, configure: {}, done: {}),
            in: .aqua, width: helmPanelWidth, height: 60)
    }

    func testDoneIsDrawnWithEveryFooterButtonSwitchedOff() {
        let reading = footer(editing: false, switchesOn: false)
        XCTAssertGreaterThan(reading.layers.count, 0,
                             "the footer drew nothing even as a rule, so no count below means anything")

        let bare = footer(editing: true, switchesOn: false)
        let full = footer(editing: true, switchesOn: true)
        XCTAssertGreaterThan(bare.layers.count, reading.layers.count, """
            arranging with all three footer buttons off draws \(bare.layers.count) layers, no more \
            than the rule alone (\(reading.layers.count)) — the row carrying «Готово» is not there, \
            and the mode has no way out
            """)
        XCTAssertEqual(bare.layers.count, full.layers.count, """
            the arranging row draws \(bare.layers.count) layers with the footer buttons off and \
            \(full.layers.count) with them on — something in it still follows switches that belong \
            to the reading row
            """)
    }
}
