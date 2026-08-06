import XCTest
import HelmUI
@testable import HelmApp

/// The width the panel has always been.
///
/// It became a setting when the panel gained its own setup bar, and a setting
/// with a wrong default is a silent redesign: nobody chose it, nobody is told,
/// and the only evidence is somebody saying the panel looks narrower than they
/// remember.
@MainActor
final class PanelWidthTests: XCTestCase {

    /// 300, which is what `helmPanelWidth` was as a constant.
    func testTheDefaultIsWhatTheConstantWas() {
        XCTAssertEqual(AppSettings.panelWidth, 300)
    }

    /// A stored value this build does not offer — from a newer version, or a
    /// hand-edited domain — falls back rather than resizing the window to
    /// something nothing can lay out in.
    func testAnUnofferedWidthFallsBack() {
        XCTAssertFalse(AppSettings.panelWidths.contains(0))
        XCTAssertTrue(AppSettings.panelWidths.contains(300))
    }

    /// What each offered width actually buys. 400 is wider tiles, not a third
    /// column: three columns at 400 pt is 120 pt a tile, under the 144 pt floor
    /// the column count is argued from.
    func testTheWidthsAreTheOnesWhereAColumnIsBought() {
        XCTAssertEqual(PanelGrid.columns(for: 300), 2)
        XCTAssertEqual(PanelGrid.columns(for: 400), 2)
        XCTAssertEqual(PanelGrid.columns(for: 480), 3)
    }
}
