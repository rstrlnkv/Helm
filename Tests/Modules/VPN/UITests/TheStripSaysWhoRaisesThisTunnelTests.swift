// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine
@testable import Module_VPN_UI

/// The strip on a card: which applications raise this tunnel, how many of them
/// are drawn, and how many are left over.
///
/// It is the card's answer to «who raises this», which is the question the flat
/// list of rules never answered — and it has to be an answer that fits in a
/// card, so it is capped and says how many it did not draw.
final class TheStripSaysWhoRaisesThisTunnelTests: XCTestCase {

    private func rule(_ vpn: String) -> VPNAppRule { VPNAppRule(vpnName: vpn) }

    /// Sorted the way the page sorts names, which is the page's business — the
    /// logic takes the order as a parameter rather than inventing one.
    private let byName: ([String]) -> [String] = { $0.sorted() }

    func testTheStripHoldsTheApplicationsPointingAtThisTunnel() {
        let strip = VPNTenants.of("One",
                                  rules: ["b": rule("One"), "a": rule("One"), "c": rule("Two")],
                                  sorted: byName)
        XCTAssertEqual(strip.shown, ["a", "b"])
        XCTAssertEqual(strip.overflow, 0)
        XCTAssertEqual(strip.total, 2)
    }

    func testATunnelNobodyPointsAtHasAnEmptyStrip() {
        let strip = VPNTenants.of("Three", rules: ["a": rule("One")], sorted: byName)
        XCTAssertTrue(strip.shown.isEmpty)
        XCTAssertEqual(strip.overflow, 0)
        XCTAssertEqual(strip.total, 0)
    }

    /// **Four, and the number is a width.** Measured at the narrowest card this
    /// app can draw — the settings column clamps to the pane, so at the minimum
    /// window a card is about 297 pt with 273 of content: the strip's own
    /// chrome plus four icons plus the overflow chip plus the notices door comes
    /// to 214. Five icons would fit there and not in a 190 pt card, which is the
    /// floor the grid still declares.
    func testTheStripIsCappedAndSaysHowManyItDidNotDraw() {
        let many = Dictionary(uniqueKeysWithValues: (1...9).map { ("app\($0)", rule("One")) })
        let strip = VPNTenants.of("One", rules: many, sorted: byName)
        XCTAssertEqual(strip.shown.count, VPNTenants.cap)
        XCTAssertEqual(strip.shown.count, 4)
        XCTAssertEqual(strip.overflow, 5)
        XCTAssertEqual(strip.total, 9)
    }

    /// «+0» is not a thing to draw, so the overflow is zero exactly when
    /// everything is on screen — at the cap, and one under it.
    func testThereIsNoPlusZero() {
        for count in 1...VPNTenants.cap {
            let rules = Dictionary(uniqueKeysWithValues: (1...count).map {
                ("app\($0)", rule("One"))
            })
            XCTAssertEqual(VPNTenants.of("One", rules: rules, sorted: byName).overflow, 0,
                           "\(count) applications reported an overflow")
        }
        let overCap = Dictionary(uniqueKeysWithValues: (1...(VPNTenants.cap + 1)).map {
            ("app\($0)", rule("One"))
        })
        XCTAssertEqual(VPNTenants.of("One", rules: overCap, sorted: byName).overflow, 1)
    }

    /// The order is the caller's, and the cap takes the *first* of it — so the
    /// icons a person sees are the same ones, in the same places, every time the
    /// page draws.
    func testTheCapTakesTheFirstOfTheCallersOrder() {
        let rules = Dictionary(uniqueKeysWithValues: ["e", "d", "c", "b", "a"].map {
            ($0, rule("One"))
        })
        XCTAssertEqual(VPNTenants.of("One", rules: rules, sorted: byName).shown,
                       ["a", "b", "c", "d"])
        XCTAssertEqual(VPNTenants.of("One", rules: rules, sorted: { $0.sorted().reversed() }).shown,
                       ["e", "d", "c", "b"])
    }

    /// A rule whose tunnel this Mac no longer has belongs to no card's strip —
    /// the page says that in one line under the grid instead.
    func testAnOrphanedRuleIsInNobodySStrip() {
        let rules = ["a": rule("Old office"), "b": rule("One")]
        XCTAssertEqual(VPNTenants.of("One", rules: rules, sorted: byName).shown, ["b"])
        XCTAssertEqual(VPNTenants.orphaned(rules, connections: ["One"]).sorted(), ["a"])
    }

    func testNothingIsOrphanedWhenEveryRulePointsAtSomethingReal() {
        XCTAssertTrue(VPNTenants.orphaned(["a": rule("One")], connections: ["One", "Two"]).isEmpty)
    }

    /// **An empty list of configurations does not orphan everything.** `scutil`
    /// can answer with nothing — a refusal, a Mac mid-boot — and a page that
    /// then reported «4 rules point at tunnels that are gone» would be shouting
    /// about a bad read.
    func testAnEmptyListOfConnectionsOrphansNothing() {
        XCTAssertTrue(VPNTenants.orphaned(["a": rule("One"), "b": rule("Two")],
                                          connections: []).isEmpty)
    }
}
