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

    // MARK: - When a figure stops being live

    /// **`speedIsStale` was a check that could not fail.** It read
    /// `speed == nil || (speedAge ?? 0) > 0`, and `speedAge` is non-nil whenever
    /// `speed` is — so the fallback never fired and every reading with an age of
    /// so much as a microsecond was stale. `var speedIsStale: Bool { true }`
    /// passed the whole suite. One case each side of the named threshold now.
    func testAFreshMeasurementIsNotStale() {
        let taken = now.addingTimeInterval(-(VPNTunnelFacts.speedGoesStaleAfter - 1))
        let facts = VPNTunnelFacts(since: nil, bytesIn: 0, bytesOut: 0,
                                   speed: VPNSpeedReading(down: 212, up: 95, rpm: 850, at: taken),
                                   now: now)
        XCTAssertFalse(facts.speedIsStale)
    }

    func testAMeasurementOlderThanTheThresholdIsStale() {
        let taken = now.addingTimeInterval(-(VPNTunnelFacts.speedGoesStaleAfter + 1))
        let facts = VPNTunnelFacts(since: nil, bytesIn: 0, bytesOut: 0,
                                   speed: VPNSpeedReading(down: 212, up: 95, rpm: 850, at: taken),
                                   now: now)
        XCTAssertTrue(facts.speedIsStale)
    }

    /// A reading stamped in the future is the clock-skew case this same
    /// initializer already refuses for `since`, and it is not a live figure
    /// either — it is a figure whose age cannot be told.
    func testAMeasurementFromTheFutureIsStale() {
        let facts = VPNTunnelFacts(since: nil, bytesIn: 0, bytesOut: 0,
                                   speed: VPNSpeedReading(down: 212, up: 95, rpm: 850,
                                                          at: now.addingTimeInterval(60)),
                                   now: now)
        XCTAssertTrue(facts.speedIsStale)
    }

    // MARK: - Counters that are not there

    /// **Absent is a state for the counters too.** The kernel has no counters for
    /// an interface that has gone, and this type could only be told `0` — which
    /// draws as a tunnel that has carried nothing, the one thing that is
    /// certainly not true of a tunnel that has been up for an hour.
    func testCountersTheKernelHadNoAnswerForAreAbsent() {
        let facts = VPNTunnelFacts(since: nil, bytesIn: nil, bytesOut: nil, speed: nil, now: now)
        XCTAssertNil(facts.bytesIn)
        XCTAssertNil(facts.bytesOut)
    }

    func testATunnelThatHasCarriedNothingSaysZero() {
        let facts = VPNTunnelFacts(since: nil, bytesIn: 0, bytesOut: 0, speed: nil, now: now)
        XCTAssertEqual(facts.bytesIn, 0, "a tunnel just raised has carried nothing, and that "
                       + "is a measurement rather than an absence")
    }
}
