// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// **The Mac whose VPN comes up at login.**
///
/// A tunnel already up when Helm starts is asked about too: the country follows
/// the state of not having one, not the transition `wasDown` reports. Otherwise
/// the most ordinary arrangement there is would draw «Traffic goes through the
/// tunnel» with no place named, for the life of the process.
///
/// Every test drives the engine through its stream and names its fake ports: a
/// default argument reaches `TraceExit`, a real request to Cloudflare.
final class ATunnelUpBeforeHelmStillNamesItsCountryTests: XCTestCase {

    /// One configuration, already `Connected` at the very first read.
    private func alreadyUp() -> FakeRunner {
        let runner = FakeRunner()
        runner.listOutput =
            "* (Connected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        runner.statusOutput = ["work": scutilStatus()]
        return runner
    }

    private func routed(_ interface: String?) -> FakeInterfaces {
        let interfaces = FakeInterfaces()
        interfaces.primary = interface
        interfaces.counters = ["utun4": (in: 4_000, out: 2_000)]
        return interfaces
    }

    private func makeEngine(_ runner: FakeRunner, news: EngineNews<VPNEngine.StatePayload>,
                            interfaces: FakeInterfaces, exit: FakeExit,
                            now: @escaping @Sendable () -> Date = Date.init) -> VPNEngine {
        VPNEngine(settings: VPNSettings.inMemory(), runner: runner, apps: FakeApps(),
                  news: news, interfaces: interfaces, exit: exit,
                  speed: FakeSpeed(), now: now, work: .inline)
    }

    /// Nothing goes down and nothing comes up: the engine reads a list on which
    /// a tunnel is already `Connected`.
    func test_a_tunnel_already_up_at_the_first_read_is_asked_about() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let exit = FakeExit()
        exit.answer = "NL"
        let engine = makeEngine(alreadyUp(), news: news,
                                interfaces: routed("utun4"), exit: exit)

        let arrived = await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }

        XCTAssertTrue(arrived, """
        the tunnel reached the page with no country. It was up before Helm was, \
        so nobody watched it come up — which is exactly the Mac whose VPN starts \
        at login, and the country was tied to the transition rather than to the \
        state of not having one.
        """)
        XCTAssertGreaterThan(exit.asks, 0, "the request was never made at all")
    }

    /// Having asked, it does not go on asking: this is the app's one request to
    /// a server that is not the update feed, and every path into a refresh
    /// reaches the gate.
    func test_the_country_is_asked_for_once_and_then_left_alone() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let exit = FakeExit()
        exit.answer = "NL"
        let engine = makeEngine(alreadyUp(), news: news,
                                interfaces: routed("utun4"), exit: exit)

        await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }
        for _ in 0..<5 {
            await refreshed(engine, on: news) { _ in true }
        }

        XCTAssertEqual(exit.asks, 1, """
        \(exit.asks) requests left this Mac for one tunnel that never moved. \
        A country on record closes the question; only the route moving reopens it.
        """)
    }

    /// An empty answer must not become a stream: a blocked host refuses at once,
    /// and without the quiet period every refresh would be another request.
    func test_an_empty_answer_is_not_retried_on_the_next_refresh() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let exit = FakeExit()
        exit.answer = nil
        let clock = TestClock(Date(timeIntervalSince1970: 1_000_000))
        let engine = makeEngine(alreadyUp(), news: news,
                                interfaces: routed("utun4"), exit: exit,
                                now: { clock.now })

        await refreshed(engine, on: news) { $0.tunnels.first?.exit != nil }
        // The assertion below is an absence, which also holds while the first
        // attempt is still out (Architecture/TestsAndMeasurement.md § What makes a check).
        await waitUntilReached("the first attempt came back", within: .seconds(5)) { exit.asks == 1 }
        for _ in 0..<3 {
            await refreshed(engine, on: news) { _ in true }
        }

        XCTAssertEqual(exit.asks, 1,
                       "an unanswered request was repeated \(exit.asks) times inside a minute")

        // And the quiet period ends rather than closing the question for good.
        clock.now = clock.now.addingTimeInterval(VPNExitAsk.quietPeriod)
        exit.answer = "DE"
        let answered = await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "DE")
        }
        XCTAssertTrue(answered, "the quiet period never ended, so one timeout cost the country for ever")
    }

    /// **A country belongs to the route it was read for.** When the route moves
    /// to Wi-Fi, a country that stayed put would be a wrong answer, where none
    /// at all is only a gap.
    func test_the_route_moving_drops_a_country_that_is_no_longer_true() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let exit = FakeExit()
        exit.answer = "NL"
        let interfaces = routed("utun4")
        let engine = makeEngine(alreadyUp(), news: news,
                                interfaces: interfaces, exit: exit)

        await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }

        interfaces.primary = "en0"
        exit.answer = "DE"
        let moved = await refreshed(engine, on: news) { $0.tunnels.first?.exit == .besideTunnel }
        XCTAssertTrue(moved, "the tunnel still claimed the route after it had moved")

        // Back through the tunnel, and the country must be the one read since
        // the move rather than the one from before it.
        interfaces.primary = "utun4"
        let reread = await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "DE")
        }
        XCTAssertTrue(reread, """
        the tunnel came back carrying «NL», which was read for a route this Mac \
        had left. A stale country reads as an answer; an absent one reads as a gap.
        """)
    }

    /// A store that could not be read answers nil, as does a Mac with no
    /// network, so nil is not a route change; otherwise every hiccup of the
    /// dynamic store would drop a good answer and buy another request.
    func test_an_unreadable_route_does_not_cost_the_country() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let exit = FakeExit()
        exit.answer = "NL"
        let interfaces = routed("utun4")
        let engine = makeEngine(alreadyUp(), news: news,
                                interfaces: interfaces, exit: exit)

        await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }
        interfaces.primary = nil
        await refreshed(engine, on: news) { _ in true }
        interfaces.primary = "utun4"
        await refreshed(engine, on: news) { _ in true }

        XCTAssertEqual(exit.asks, 1,
                       "an unreadable route was read as the machine moving, and cost a request")
    }

    /// **A request that is still out when a tunnel comes up.**
    ///
    /// The tunnel coming up forces a fresh check, and `Task.cancel()` does not
    /// silence the cancelled run: its completion still arrives. Landing it would
    /// write a reading for a route the Mac has left, and clear the «a request is
    /// out» flag while one is.
    func test_an_answer_that_has_been_superseded_is_not_written() async {
        let news = EngineNews<VPNEngine.StatePayload>()
        let exit = FakeExit()
        // The first ask is held open and would answer «NL»; the forced second
        // one answers «DE», which is the reading that belongs to the route.
        exit.queued = ["NL", "DE"]
        exit.holdsFirstUntilReleased = true

        let runner = FakeRunner()
        runner.listOutput =
            "* (Disconnected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        runner.statusOutput = ["work": scutilStatus()]
        let interfaces = routed("en0")
        let engine = makeEngine(runner, news: news, interfaces: interfaces, exit: exit)

        // A first reading with nothing up, so the tunnel below is seen coming
        // up: `wasDown` needs a previous reading.
        await refreshed(engine, on: news) { _ in true }

        // Now it is up and holds the route: the gate asks, and that request is
        // held open.
        runner.listOutput =
            "* (Connected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        interfaces.primary = "utun4"
        await refreshed(engine, on: news) { $0.tunnels.count == 1 }
        await waitUntilReached("the first request left", within: .seconds(5)) { exit.asks >= 1 }

        // It drops and comes back, which forces a second check while the first
        // is still out.
        runner.listOutput =
            "* (Disconnected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        await refreshed(engine, on: news) { $0.tunnels.isEmpty }
        runner.listOutput =
            "* (Connected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        let backWithACountry = await refreshed(engine, on: news) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "DE")
        }
        XCTAssertTrue(backWithACountry, "the second request's answer never reached the page")

        // And now the first one is let go. Its answer is older than what is on
        // the page and must be dropped rather than written over it.
        exit.release()
        // An absence holds trivially while the held run is on its way back, and
        // there is no count of completions to wait on; the second request's
        // answer above is the control that the path speaks.
        await grace(0.4)
        let drawn = await lastState(on: news)?.tunnels.first?.exit
        XCTAssertEqual(drawn, .throughTunnel(countryCode: "DE"), """
        a superseded answer was written over a newer one. Cancelling a URL load         does not silence its completion, so the run that comes back last wins         unless something tells the two apart.
        """)
    }
}
