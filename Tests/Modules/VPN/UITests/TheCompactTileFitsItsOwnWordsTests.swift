// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import AppKit
import HelmUI
import XCTest
@testable import Module_VPN_UI

/// **A 1×1 tile is 144 pt wide and cannot grow.**
///
/// `PanelGrid.minimumTile` is the floor a tile is laid out at, and the panel is
/// drawn at exactly `narrowestPanel` — two columns of it — so this is not a
/// hypothetical width. Inside, `helmPanelCard` takes `HelmSpace.s5` off each
/// side, which leaves 120 pt for anything the widget draws.
///
/// The tile's own sentence did not fit: «Nenhuma VPN configurada» is 142 pt of
/// 120 in Portuguese, and Japanese, German and Russian are over too — measured
/// at `HelmText.rowDetail`, which is what both `HelmWidgetUnmeasured` and
/// `HelmWidgetFigure`'s label draw in. `HelmWidgetUnmeasured` is
/// `fixedSize(horizontal: false, vertical: true)`, so what a too-long string
/// does is wrap: the smallest tile in the panel becomes two lines in four of
/// the eight languages and one line in the other four, in a grid whose whole
/// argument is that a row of tiles reads as a row.
///
/// Measured rather than looked at, because the widest of the eight is
/// Portuguese and nobody runs the app in it by accident.
final class TheCompactTileFitsItsOwnWordsTests: XCTestCase {

    /// What `HelmText.rowDetail` is on macOS. Both strings below are drawn in
    /// it, and the absolute number matters less than that the budget and the
    /// strings are measured with the same one.
    private func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11)]).width
    }

    /// The tile's own arithmetic, from the grid rather than from a number typed
    /// here: a hand-written 144 would go on passing after the floor moved.
    private var budget: CGFloat {
        PanelGrid.tileWidth(for: PanelGrid.narrowestPanel) - HelmSpace.s5 * 2
    }

    /// Everything `VPNCompactWidget` puts under its header. The figure itself is
    /// «2/3» and answers to nothing; these two are words, and words are what
    /// translate into something longer.
    private func drawn(_ language: AppLanguage) -> [(String, String)] {
        [("noVPNs", VPNStr.noVPNs(language: language)),
         ("connections", VPNStr.connections(language: language))]
    }

    func testEveryWordTheCompactTileDrawsFitsOneLineOfIt() {
        var offenders: [String] = []
        for language in AppLanguage.allCases {
            for (name, text) in drawn(language) where width(text) > budget {
                offenders.append("  \(language.rawValue) \(name): «\(text)» is "
                                 + "\(String(format: "%.1f", width(text))) pt of \(budget)")
            }
        }
        XCTAssertTrue(offenders.isEmpty,
                      "\(offenders.count) string(s) are wider than the 1×1 tile they are drawn "
                      + "in, so the smallest tile in the panel wraps to two lines in some "
                      + "languages and not in others:\n" + offenders.sorted().joined(separator: "\n"))
    }

    /// The measurement this file is worth nothing without: that the instrument
    /// still sees the defect it was written from. The four that were over ran
    /// from 121 pt to 142 against 120, so a threshold set a little high would
    /// look exactly like a pass.
    func testTheInstrumentStillFailsTheSentenceThisReplaced() {
        // The Portuguese and Japanese of the key that was deleted, as they
        // shipped — kept as literals on purpose: a test that reads the tables
        // for its own control loses the control when the tables change.
        XCTAssertGreaterThan(width("Nenhuma VPN configurada"), budget,
                             "the widest string this tile ever drew now fits, so nothing here "
                             + "can fail")
        XCTAssertGreaterThan(width("VPN が設定されていません"), budget)
    }

    /// And the budget is a real reading rather than something that came out
    /// zero: a `budget` of nothing would fail every string and one of everything
    /// would pass every string.
    func testTheBudgetIsTheTileMinusItsPadding() {
        XCTAssertEqual(budget, PanelGrid.minimumTile - HelmSpace.s5 * 2, accuracy: 0.01,
                       "the panel at its narrowest no longer lays a tile out at the floor, so "
                       + "this file is measuring against something else")
        XCTAssertGreaterThan(budget, 100)
    }
}
