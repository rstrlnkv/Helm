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
                                        tunnelIsPrimary: nil, countryCode: "NL")
        XCTAssertEqual(verdict, .throughTunnel(countryCode: "NL"))
    }

    /// The tunnel is up and the machine is on the internet through Wi-Fi. This
    /// is the state the whole check exists for.
    func testTrafficOutsideTheTunnelIsNamedOutright() {
        let verdict = VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: "en0",
                                        tunnelIsPrimary: nil, countryCode: "DE")
        XCTAssertEqual(verdict, .besideTunnel)
    }

    /// The country service did not answer. The routing half still knows the
    /// answer to the important question, so the verdict stands without a place.
    func testAMissingCountryDoesNotCostTheVerdict() {
        let verdict = VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: "utun4",
                                        tunnelIsPrimary: nil, countryCode: nil)
        XCTAssertEqual(verdict, .throughTunnel(countryCode: nil))
    }

    /// Nothing could be read about the route. Not a verdict — an unknown, drawn
    /// as one.
    func testNoRoutingReadingIsUnknownRatherThanGood() {
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: nil, primaryInterface: "en0",
                                         tunnelIsPrimary: true, countryCode: "NL"), .unknown)
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun4", primaryInterface: nil,
                                         tunnelIsPrimary: nil, countryCode: "NL"), .unknown)
    }

    // MARK: - The tool's own answer to the same question

    /// **The store can fail to answer, and the same read that named the
    /// interface already carries the routing flag.** `scutil --nc status` ends
    /// with `IsPrimaryInterface : 1`, so a dynamic store that could not be
    /// opened costs the verdict nothing. Preferred the other way round —
    /// store first — because the global entry is the routing table's own
    /// answer, while the flag is the connection's view of it.
    func testTheToolsFlagAnswersWhenTheStoreCannot() {
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun8", primaryInterface: nil,
                                         tunnelIsPrimary: true, countryCode: "NL"),
                       .throughTunnel(countryCode: "NL"))
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun8", primaryInterface: nil,
                                         tunnelIsPrimary: false, countryCode: "NL"),
                       .besideTunnel)
    }

    /// And where both can be read, the routing table decides — a flag that has
    /// gone stale must not overturn what the route says now.
    func testTheStoreDecidesWhenBothCanBeRead() {
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun8", primaryInterface: "en0",
                                         tunnelIsPrimary: true, countryCode: "NL"),
                       .besideTunnel)
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun8", primaryInterface: "utun8",
                                         tunnelIsPrimary: false, countryCode: "NL"),
                       .throughTunnel(countryCode: "NL"))
    }

    /// Neither source answered. Still an unknown, and never dressed as either
    /// verdict.
    func testNeitherSourceIsStillUnknown() {
        XCTAssertEqual(VPNExitVerdict.of(tunnelInterface: "utun8", primaryInterface: nil,
                                         tunnelIsPrimary: nil, countryCode: "NL"), .unknown)
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
