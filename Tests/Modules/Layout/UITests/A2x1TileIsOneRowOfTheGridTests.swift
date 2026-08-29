import XCTest
import SwiftUI
@testable import Module_Layout_UI
@testable import Module_Layout_Engine
import HelmUI
import HelmTestSupport

/// 2×1 is «every column, one row». It stopped being one.
///
/// The fortnight drawing and the time estimate were given to every size that
/// was not 1×1, and the 2×1 tile went to 202 pt against Disk's 110 — a Keyboard
/// tile twice the height of every other module's, which makes the row it sits
/// in about Keyboard whatever the person arranged.
///
/// **Asserted without a threshold.** A number like «not taller than 170» is a
/// number somebody raises the day it fails, and it says nothing about German.
/// What is asserted instead is that the 2×1 tile does not *depend* on the two
/// things only the tall tile draws: change the fortnight and change the
/// characters, and if what is drawn moves, the drawing came back.
///
/// **Ink, not height.** Height was the first reading and it was blind: the
/// fortnight is a fixed 26 pt whatever the days hold, so a tall tile drawing a
/// quiet fortnight and a busy one measured 256.0 both times and the half of
/// this test that exists to prove the other half is not vacuous passed nothing.
/// Pixels see a bar that grew; a bounding box does not.
@MainActor
final class A2x1TileIsOneRowOfTheGridTests: XCTestCase {

    private func state(recent: [Int], characters: Int) -> LayoutState {
        let figures = LedgerFigures(words: 17, characters: characters)
        return LayoutState(
            enabled: true, automatic: true, suspended: false,
            lastConversion: ConversionEvent(before: "vtymit", after: "меньше",
                                            app: "com.apple.Safari"),
            lastConversionUndone: false,
            totals: ConversionTotals(today: figures, week: figures, month: figures,
                                     year: figures, allTime: figures,
                                     since: nil, recent: recent))
    }

    private func ink(_ state: LayoutState, _ size: PanelWidgetSize) throws -> Int {
        let render = MountedRender(LayoutTile(state: state, size: size, period: .month),
                                   width: 280, height: 600, appearance: .aqua)
        defer { render.drop() }
        return try XCTUnwrap(render.settledInk())
    }

    private let quiet = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    private let busy = [3, 9, 1, 0, 7, 4, 2, 8, 1, 0, 5, 6, 2, 9]

    func testTheFortnightDoesNotReachTheWideTile() throws {
        XCTAssertEqual(try ink(state(recent: quiet, characters: 40), .wide),
                       try ink(state(recent: busy, characters: 40), .wide),
                       "a 2×1 tile that changes with the ledger is drawing the fortnight")
    }

    func testTheEstimateDoesNotReachTheWideTile() throws {
        XCTAssertEqual(try ink(state(recent: quiet, characters: 40), .wide),
                       try ink(state(recent: quiet, characters: 40_000), .wide),
                       "a 2×1 tile that changes with the characters is drawing the estimate")
    }

    /// The other half of each claim: the tall tile *does* draw both, so the two
    /// tests above are not passing because nothing is drawn anywhere.
    func testTheFortnightDoesReachTheTallTile() throws {
        XCTAssertNotEqual(try ink(state(recent: quiet, characters: 40), .tall),
                          try ink(state(recent: busy, characters: 40), .tall),
                          "the 2×N tile is not drawing the fortnight either")
    }

    func testTheEstimateDoesReachTheTallTile() throws {
        XCTAssertNotEqual(try ink(state(recent: quiet, characters: 40), .tall),
                          try ink(state(recent: quiet, characters: 40_000), .tall),
                          "the 2×N tile is not drawing the estimate either")
    }
}
