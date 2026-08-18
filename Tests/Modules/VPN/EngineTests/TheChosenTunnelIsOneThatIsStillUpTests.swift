// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_VPN_Engine

/// **A selection pointing at a tunnel that is gone is an empty strip.**
///
/// The switcher's selection is a state of one visit — a name, held by the page,
/// against a list the engine rewrites whenever the network moves. So the name
/// can name nothing at any moment: the tunnel dropped, or Helm was told to
/// disconnect it, and the page still holds the word. Answering nil there empties
/// a card that has two other tunnels to draw.
///
/// The fallback is the *first*, which is the one carrying the default route
/// (`VPNTunnelChoice.primaryFirst`) — «the first» means something exactly
/// because of that ordering, and the two live in one file for that reason.
final class TheChosenTunnelIsOneThatIsStillUpTests: XCTestCase {

    private func tunnel(_ name: String,
                        exit: VPNExitVerdict = .besideTunnel) -> VPNTunnelState {
        VPNTunnelState(name: name, interface: "utun\(name.count)", since: nil,
                       bytesIn: nil, bytesOut: nil, exit: exit, speed: nil)
    }

    // MARK: - Which tunnel the strip is about

    func testTheTunnelThePersonPickedIsTheOneDrawn() {
        let up = [tunnel("home"), tunnel("cafe"), tunnel("work")]
        XCTAssertEqual(VPNTunnelChoice.chosen("cafe", among: up)?.name, "cafe")
    }

    /// The rule this file exists for.
    func testAChosenTunnelThatHasGoneFallsBackToTheFirst() {
        let up = [tunnel("home"), tunnel("cafe")]
        XCTAssertEqual(VPNTunnelChoice.chosen("work", among: up)?.name, "home", """
            the strip is empty while two tunnels are up: the selection still \
            names one that dropped, and nothing put it back on the first
            """)
    }

    func testNoSelectionAtAllIsTheFirst() {
        XCTAssertEqual(VPNTunnelChoice.chosen(nil, among: [tunnel("home"), tunnel("cafe")])?.name,
                       "home")
    }

    /// Nothing up is no strip — which is the page's own `if let`, and the only
    /// nil this answers.
    func testNothingUpChoosesNothing() {
        XCTAssertNil(VPNTunnelChoice.chosen("home", among: []))
        XCTAssertNil(VPNTunnelChoice.chosen(nil, among: []))
    }

    // MARK: - What «the first» means

    func testTheTunnelCarryingTheDefaultRouteComesFirst() {
        let ordered = VPNTunnelChoice.primaryFirst([
            tunnel("home"),
            tunnel("work", exit: .throughTunnel(countryCode: "NL")),
            tunnel("cafe")
        ])
        XCTAssertEqual(ordered.map(\.name), ["work", "home", "cafe"], """
            the tunnel the traffic actually leaves through is not first, so \
            «the first» — which is what a lost selection falls back to and what \
            the page opens on — names whichever configuration was made earliest
            """)
    }

    /// The tail keeps the tool's own order, the way `VPNConnectionOrder` leaves
    /// it: a list re-sorted by name moves every segment whenever a tunnel comes
    /// up, which is motion on a row nobody touched.
    func testTheRestKeepTheOrderTheToolGaveThem() {
        let ordered = VPNTunnelChoice.primaryFirst([
            tunnel("zeta"), tunnel("alpha"),
            tunnel("mid", exit: .throughTunnel(countryCode: nil)), tunnel("beta")
        ])
        XCTAssertEqual(ordered.map(\.name), ["mid", "zeta", "alpha", "beta"])
    }

    /// Two tunnels up and neither holding the route is an ordinary Mac — the
    /// route is on Wi-Fi. Nothing is promoted, and the list is untouched.
    func testWithNoRoutedTunnelTheListIsLeftExactlyAsItCame() {
        let up = [tunnel("home"), tunnel("cafe"), tunnel("work", exit: .unknown)]
        XCTAssertEqual(VPNTunnelChoice.primaryFirst(up).map(\.name), up.map(\.name))
    }

    // MARK: - The predicate both sides read

    /// The engine refuses a measurement on a tunnel this is false of and the
    /// page draws a sentence instead of the button for the same tunnel. One
    /// predicate, so the two cannot disagree about which tunnel a fifteen-second
    /// run belongs to.
    func testOnlyTheRoutedVerdictCarriesTheDefaultRoute() {
        XCTAssertTrue(VPNExitVerdict.throughTunnel(countryCode: "NL").carriesTheDefaultRoute)
        XCTAssertTrue(VPNExitVerdict.throughTunnel(countryCode: nil).carriesTheDefaultRoute)
        XCTAssertFalse(VPNExitVerdict.besideTunnel.carriesTheDefaultRoute)
        XCTAssertFalse(VPNExitVerdict.unknown.carriesTheDefaultRoute, """
            a routing reading that could not be made is being read as permission \
            to attribute a measurement — an unbound run follows whatever route \
            there is, and this verdict is precisely «nobody knows what that is»
            """)
    }
}
