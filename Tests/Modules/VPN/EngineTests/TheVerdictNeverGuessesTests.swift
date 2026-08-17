// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// «Трафик идёт через туннель» is a claim, and it is made from two readings that
/// fail independently. The one thing this must never do is answer «через
/// туннель» because a request failed.
final class TheVerdictNeverGuessesTests: XCTestCase {

    func testTrafficIsInTheTunnelWhenTheDefaultRouteIsTheTunnelsInterface() {
        let verdict = VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: "utun4",
                                        countryCode: "NL")
        XCTAssertEqual(verdict, .throughTunnel(countryCode: "NL"))
    }

    /// The tunnel is up and the machine is on the internet through Wi-Fi. This
    /// is the state the whole check exists for.
    func testTrafficOutsideTheTunnelIsNamedOutright() {
        let verdict = VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: "en0",
                                        countryCode: "DE")
        XCTAssertEqual(verdict, .besideTunnel)
    }

    /// The country service did not answer. The routing half still knows the
    /// answer to the important question, so the verdict stands without a place.
    func testAMissingCountryDoesNotCostTheVerdict() {
        let verdict = VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: "utun4",
                                        countryCode: nil)
        XCTAssertEqual(verdict, .throughTunnel(countryCode: nil))
    }

    /// Nothing could be read about the route. Not a verdict — an unknown, drawn
    /// as one.
    func testNoRoutingReadingIsUnknownRatherThanGood() {
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: nil, primaryInterface: "en0",
                                         countryCode: "NL"), .unknown)
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: nil,
                                         countryCode: "NL"), .unknown)
    }

    /// A synthesised enum codec can decode a case and silently drop its
    /// payload — which here would put «через туннель — nowhere» on screen.
    /// Round-trip every case, the country included.
    func testEncodingAndDecodingPreservesEveryCaseAndItsCountry() throws {
        let cases: [VPNExitVerdict] = [
            .throughTunnel(countryCode: "NL"),
            .throughTunnel(countryCode: nil),
            .besideTunnel,
            .unknown,
        ]
        for verdict in cases {
            let data = try JSONEncoder().encode(verdict)
            let decoded = try JSONDecoder().decode(VPNExitVerdict.self, from: data)
            XCTAssertEqual(decoded, verdict)
        }
    }
}
