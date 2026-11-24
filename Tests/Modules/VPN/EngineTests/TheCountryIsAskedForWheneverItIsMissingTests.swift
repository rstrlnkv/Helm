// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// The country is asked for whenever «a tunnel is up and has no country»,
/// not on the event of Helm watching a tunnel go down→up — so a Mac whose
/// VPN comes up at login, before the menu bar app, gets one too.
final class TheCountryIsAskedForWheneverItIsMissingTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Something is up, nothing is on record, nobody has asked. Nothing about
    /// *how* the tunnel came up appears here, which is the point.
    func testATunnelWithNoCountryIsAsked() {
        XCTAssertTrue(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: false,
                                        lastAsked: nil, now: t0))
    }

    func testNothingUpIsNothingToAsk() {
        XCTAssertFalse(VPNExitAsk.should(tunnelIsUp: false, region: nil, asking: false,
                                         lastAsked: nil, now: t0))
    }

    /// A country already on record closes the question. The route moving is what
    /// reopens it, and that is `routeMoved` below rather than a second reading
    /// taken on top of a good one.
    func testACountryOnRecordIsNotAskedAgain() {
        XCTAssertFalse(VPNExitAsk.should(tunnelIsUp: true, region: "NL", asking: false,
                                         lastAsked: nil, now: t0))
    }

    /// **The gate that keeps one connect from becoming a request per poll.**
    /// `VPNEngine.poll` re-reads many times behind a single connect and the probe
    /// waits up to eight seconds, so without this every read would start a
    /// request while the first was still out.
    func testARequestInFlightIsNotJoinedByAnother() {
        XCTAssertFalse(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: true,
                                         lastAsked: nil, now: t0))
    }

    /// An attempt that came back empty stands for a minute. This is the app's
    /// one request to a server that is not the update feed, and a refresh loop
    /// over a blocked host must not turn it into a stream.
    func testAnEmptyAnswerIsNotRetriedImmediately() {
        XCTAssertFalse(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: false,
                                         lastAsked: t0, now: t0.addingTimeInterval(1)))
        XCTAssertFalse(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: false,
                                         lastAsked: t0,
                                         now: t0.addingTimeInterval(VPNExitAsk.quietPeriod - 1)))
    }

    /// And it does not stand for ever: a person who plugged the network back in
    /// gets an answer without having to touch the tunnel.
    func testTheQuietPeriodEnds() {
        XCTAssertTrue(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: false,
                                        lastAsked: t0,
                                        now: t0.addingTimeInterval(VPNExitAsk.quietPeriod)))
        XCTAssertTrue(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: false,
                                        lastAsked: t0,
                                        now: t0.addingTimeInterval(VPNExitAsk.quietPeriod * 3)))
    }

    /// A clock that went backwards — a person setting the date, or NTP stepping
    /// it — must not open the gate. A negative interval is not a minute having
    /// passed, and reading it as one is the retry loop this quiet period exists
    /// to prevent.
    func testAClockThatWentBackwardsDoesNotOpenTheGate() {
        XCTAssertFalse(VPNExitAsk.should(tunnelIsUp: true, region: nil, asking: false,
                                         lastAsked: t0, now: t0.addingTimeInterval(-3600)))
    }

    // MARK: - Whether the answer on record still belongs to this route

    func testTheRouteMovingIsAMove() {
        XCTAssertTrue(VPNExitAsk.routeMoved(from: "en0", to: "utun4"))
        XCTAssertTrue(VPNExitAsk.routeMoved(from: "utun4", to: "utun6"))
    }

    func testTheSameRouteIsNotAMove() {
        XCTAssertFalse(VPNExitAsk.routeMoved(from: "utun4", to: "utun4"))
    }

    /// **Nil on either side is not a move**: `VPNInterfacePort.primaryInterface`
    /// answers nil both for a Mac with no network and for a store that could not
    /// be read, so a nil taken as a route change would drop the country every
    /// time the dynamic store stuttered — and asking again is a request.
    func testAnUnreadableRouteIsNotAMove() {
        XCTAssertFalse(VPNExitAsk.routeMoved(from: "utun4", to: nil))
        XCTAssertFalse(VPNExitAsk.routeMoved(from: nil, to: "utun4"))
        XCTAssertFalse(VPNExitAsk.routeMoved(from: nil, to: nil))
    }
}
