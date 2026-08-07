import XCTest
import HelmRuntime
import HelmUI
@testable import HelmApp

/// The width the panel has always been, and the reason it is not a choice.
@MainActor
final class PanelWidthTests: XCTestCase {

    /// Two columns, at the width Helm ships. The grid still derives the count
    /// from a number rather than holding one of its own — that is the rule from
    /// step one — and this is the only number it is ever given.
    ///
    /// **Read from the constant, not written out.** It said 300, the panel
    /// moved to 320, and the test went on passing because both answer two — a
    /// check that cannot fail for the thing it is named after. Reading
    /// `helmPanelWidth` is what makes it a check at all: change the panel to a
    /// width that buys a third column and this is what says so.
    func testTheShippedWidthGivesTwoColumns() {
        XCTAssertEqual(PanelGrid.columns(for: helmPanelWidth), 2)
    }

    /// What a wider panel would have bought, kept as an assertion rather than
    /// as a setting: 400 is wider tiles, not a third column, because three
    /// columns at 400 pt is 120 pt a tile — under the 144 pt floor the count is
    /// argued from. 480 is where the third column is actually paid for, and it
    /// is a grid nobody asked a menu-bar panel for.
    func testWhatTheWidthsWouldHaveBought() {
        XCTAssertEqual(PanelGrid.columns(for: 400), 2)
        XCTAssertEqual(PanelGrid.columns(for: 480), 3)
    }

    /// The key the setting wrote is cleared at launch, so it does not sit in
    /// somebody's defaults forever looking like a live value.
    func testTheKeyItWroteIsRetired() {
        XCTAssertTrue(ObsoleteDefaults.retired.contains("module.app.panelWidth"))
    }
}
