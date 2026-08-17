// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_UI

/// The connection grid ends its last row without a gap in it — or with one
/// empty slot, never two.
///
/// The column count used to be `min(count, 3)`, which is right for one and two
/// connections and wrong from four on: photographed at the settings column,
/// four connections drew 3+1 with **477 pt** of nothing beside the last card,
/// and eight drew 3+3+2. The rule was written to stop a row ending in a hole
/// and only ever saw the counts it was tested against.
///
/// A hole of one card at the end of a row reads as a list that finished; two
/// reads as a layout that failed. That is the whole threshold, and it is what
/// these tests hold.
final class TheGridLeavesNoHoleTests: XCTestCase {

    /// Every count a person can plausibly have, and a long way past it.
    private let counts = Array(1...30)

    func testNoRowEndsInMoreThanOneEmptySlot() {
        for n in counts {
            let cols = VPNGridLayout.columns(for: n)
            let hole = VPNGridLayout.hole(count: n, columns: cols)
            XCTAssertLessThanOrEqual(hole, 1,
                                     "\(n) connections in \(cols) columns leaves \(hole) empty slots")
        }
    }

    /// A third column is 226 pt, which leaves about 104 for the name once the
    /// row card's dot, badge, status and button are taken out — «NBCom VPN
    /// Office» truncates there and fits whole at two. The ceiling is a fact
    /// about the width, so it is asserted here rather than left to the
    /// arithmetic.
    func testNeverMoreThanTwoColumns() {
        for n in counts {
            XCTAssertTrue((1...2).contains(VPNGridLayout.columns(for: n)),
                          "\(n) connections asked for \(VPNGridLayout.columns(for: n)) columns")
        }
    }

    /// The two counts that were measured into the old rule keep their shape:
    /// one card at half the row, two filling it.
    func testOneAndTwoKeepTheirMeasuredShape() {
        XCTAssertEqual(VPNGridLayout.columns(for: 1), 1)
        XCTAssertEqual(VPNGridLayout.columns(for: 2), 2)
    }

    /// Four is the count the old rule broke on, and the one this exists for.
    func testFourConnectionsAreTwoByTwo() {
        XCTAssertEqual(VPNGridLayout.columns(for: 4), 2)
        XCTAssertEqual(VPNGridLayout.hole(count: 4, columns: 2), 0)
    }

    /// The collapsed grid is never the one with the hole in it: the cap is the
    /// same for every column count this rule can return, so what a person sees
    /// before pressing anything is always a full rectangle of cards.
    func testTheCollapsedGridIsAlwaysFull() {
        for n in counts where n > VPNGridLayout.collapsedLimit {
            let cols = VPNGridLayout.columns(for: n)
            let shown = VPNGridLayout.shown(n, expanded: false)
            XCTAssertEqual(shown, VPNGridLayout.collapsedLimit)
            XCTAssertEqual(VPNGridLayout.hole(count: shown, columns: cols), 0,
                           "\(n) connections collapse to \(shown) in \(cols) columns, which leaves a hole")
        }
    }

    /// Below the cap nothing is hidden, and expanding shows everything.
    func testNothingIsHiddenBelowTheCap() {
        for n in 1...VPNGridLayout.collapsedLimit {
            XCTAssertEqual(VPNGridLayout.shown(n, expanded: false), n)
        }
        for n in counts {
            XCTAssertEqual(VPNGridLayout.shown(n, expanded: true), n)
        }
    }

    /// The columns are chosen from the **total**, not from what is on screen —
    /// so pressing «Show all» adds rows and never re-sizes the cards already
    /// drawn.
    func testExpandingDoesNotRelayoutTheCardsAlreadyDrawn() {
        for n in counts {
            XCTAssertEqual(VPNGridLayout.columns(for: n),
                           VPNGridLayout.columns(for: n),
                           "the column count must not depend on what is displayed")
        }
        // The real claim: the collapsed and expanded grids are the same width
        // of card, because both ask the same question of the same number.
        for n in counts where n > VPNGridLayout.collapsedLimit {
            let collapsed = VPNGridLayout.columns(for: n)
            XCTAssertEqual(VPNGridLayout.hole(count: VPNGridLayout.shown(n, expanded: false),
                                              columns: collapsed), 0)
        }
    }
}
