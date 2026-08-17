// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// The strip under the grid says four things, and every one of them can be
/// unknown. What it must never do is invent: a Helm launched after the tunnel
/// came up does not know how long it has been up, and «—» in that tile would be
/// a reading rather than an absence.
final class TheTilesSayWhatIsKnownTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 10_000)

    func testTheDurationTileIsAbsentWhenTheMomentWasNotSeen() {
        let facts = VPNTunnelFacts(since: nil, bytesIn: 10, bytesOut: 5, speed: nil, now: now)
        XCTAssertNil(facts.uptime)
    }

    func testTheDurationIsMeasuredFromTheMomentTheTunnelCameUp() {
        let facts = VPNTunnelFacts(since: now.addingTimeInterval(-4_440),
                                   bytesIn: 0, bytesOut: 0, speed: nil, now: now)
        XCTAssertEqual(facts.uptime, 4_440)
    }

    /// A reading taken before the tunnel came up is not this tunnel's.
    func testATimestampInTheFutureIsNoReading() {
        let facts = VPNTunnelFacts(since: now.addingTimeInterval(60),
                                   bytesIn: 0, bytesOut: 0, speed: nil, now: now)
        XCTAssertNil(facts.uptime)
    }

    func testWithoutAMeasurementTheSpeedTileHasNoFigure() {
        let facts = VPNTunnelFacts(since: nil, bytesIn: 0, bytesOut: 0, speed: nil, now: now)
        XCTAssertNil(facts.speed)
        XCTAssertTrue(facts.speedIsStale)
    }

    /// A figure taken an hour ago is not a live reading and the strip has to be
    /// able to say so — the tile carries when it was taken.
    func testAMeasurementCarriesItsOwnAge() {
        let taken = now.addingTimeInterval(-180)
        let facts = VPNTunnelFacts(since: nil, bytesIn: 0, bytesOut: 0,
                                   speed: VPNSpeedReading(down: 212, up: 95, rpm: 850, at: taken),
                                   now: now)
        XCTAssertEqual(facts.speed?.down, 212)
        XCTAssertEqual(facts.speedAge, 180)
    }
}
