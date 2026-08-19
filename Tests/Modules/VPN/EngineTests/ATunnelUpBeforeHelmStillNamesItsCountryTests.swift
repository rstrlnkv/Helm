// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **The Mac whose VPN comes up at login.**
///
/// The exit check hung off one event — a service seen down at one reading and up
/// at the next — so a tunnel that was already up when Helm started was never
/// asked about. `wasDown` is right to answer false there and says why; what was
/// wrong is that the country followed it. The verdict line then drew «Traffic
/// goes through the tunnel» with the half that names a place simply missing, for
/// the whole life of the process, on the most ordinary arrangement there is.
///
/// Every test here drives the engine through the wire rather than reading a
/// private field, and each names its fake ports: a default argument here reaches
/// `TraceExit`, which is a real request to Cloudflare from a test run.
final class ATunnelUpBeforeHelmStillNamesItsCountryTests: XCTestCase {

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    /// One configuration, already `Connected` at the very first read — which is
    /// what `--nc list` says on a Mac whose tunnel was raised before Helm was.
    private func alreadyUp() -> FakeRunner {
        let runner = FakeRunner()
        runner.listOutput =
            "* (Connected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        runner.statusOutput = ["work": """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun4
          }
        }
        """]
        return runner
    }

    private func routed(_ interface: String?) -> FakeInterfaces {
        let interfaces = FakeInterfaces()
        interfaces.primary = interface
        interfaces.counters = ["utun4": (in: 4_000, out: 2_000)]
        return interfaces
    }

    private func makeEngine(_ runner: FakeRunner, transport: LocalTransport,
                            interfaces: FakeInterfaces, exit: FakeExit,
                            now: @escaping @Sendable () -> Date = Date.init) -> VPNEngine {
        VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                  transport: transport, interfaces: interfaces, exit: exit,
                  speed: FakeSpeed(), now: now, work: .inline)
    }

    /// The regression itself. Nothing goes down and nothing comes up: the engine
    /// simply reads a list on which a tunnel is already `Connected`.
    func test_a_tunnel_already_up_at_the_first_read_is_asked_about() async {
        let transport = LocalTransport()
        let exit = FakeExit()
        exit.answer = "NL"
        let engine = makeEngine(alreadyUp(), transport: transport,
                                interfaces: routed("utun4"), exit: exit)

        let arrived = await refreshed(engine, on: transport) {
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

    /// And having asked, it does not go on asking. This is the app's one request
    /// to a server that is not the update feed, and every path into the module's
    /// refresh reaches the gate — a page opening, the panel becoming key, the
    /// poll behind a connect re-reading up to 26 times.
    func test_the_country_is_asked_for_once_and_then_left_alone() async {
        let transport = LocalTransport()
        let exit = FakeExit()
        exit.answer = "NL"
        let engine = makeEngine(alreadyUp(), transport: transport,
                                interfaces: routed("utun4"), exit: exit)

        await refreshed(engine, on: transport) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }
        for _ in 0..<5 {
            await refreshed(engine, on: transport) { _ in true }
        }

        XCTAssertEqual(exit.asks, 1, """
        \(exit.asks) requests left this Mac for one tunnel that never moved. \
        A country on record closes the question; only the route moving reopens it.
        """)
    }

    /// An empty answer must not become a stream. The probe is refused in one go
    /// by a blocked host, and without the quiet period every refresh behind that
    /// refusal is another request.
    func test_an_empty_answer_is_not_retried_on_the_next_refresh() async {
        let transport = LocalTransport()
        let exit = FakeExit()
        exit.answer = nil
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let engine = makeEngine(alreadyUp(), transport: transport,
                                interfaces: routed("utun4"), exit: exit,
                                now: { clock.now })

        await refreshed(engine, on: transport) { $0.tunnels.first?.exit != nil }
        // Long enough for the request to have come back empty: the assertion
        // below is an absence, and an absence also holds while the first attempt
        // is still out — which would make this pass with the gate deleted
        // (CLAUDE.md § a test asserting an absence).
        await waitUntil("the first attempt came back") { exit.asks == 1 }
        for _ in 0..<3 {
            await refreshed(engine, on: transport) { _ in true }
        }

        XCTAssertEqual(exit.asks, 1,
                       "an unanswered request was repeated \(exit.asks) times inside a minute")

        // And the quiet period ends rather than closing the question for good.
        clock.now = clock.now.addingTimeInterval(VPNExitAsk.quietPeriod)
        exit.answer = "DE"
        let answered = await refreshed(engine, on: transport) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "DE")
        }
        XCTAssertTrue(answered, "the quiet period never ended, so one timeout cost the country for ever")
    }

    /// **A country belongs to the route it was read for.** The tunnel holds the
    /// default route and is asked about; the route then moves to Wi-Fi, which is
    /// a different exit — and a country that stayed put would be an answer,
    /// where none at all is only a gap.
    func test_the_route_moving_drops_a_country_that_is_no_longer_true() async {
        let transport = LocalTransport()
        let exit = FakeExit()
        exit.answer = "NL"
        let interfaces = routed("utun4")
        let engine = makeEngine(alreadyUp(), transport: transport,
                                interfaces: interfaces, exit: exit)

        await refreshed(engine, on: transport) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }

        interfaces.primary = "en0"
        exit.answer = "DE"
        let moved = await refreshed(engine, on: transport) { $0.tunnels.first?.exit == .besideTunnel }
        XCTAssertTrue(moved, "the tunnel still claimed the route after it had moved")

        // Back through the tunnel, and the country must be the one read since
        // the move rather than the one from before it.
        interfaces.primary = "utun4"
        let reread = await refreshed(engine, on: transport) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "DE")
        }
        XCTAssertTrue(reread, """
        the tunnel came back carrying «NL», which was read for a route this Mac \
        had left. A stale country reads as an answer; an absent one reads as a gap.
        """)
    }

    /// A store that could not be read answers nil, and so does a Mac with no
    /// network at all — so nil must not be taken for a route change. Taken for
    /// one, every hiccup of the dynamic store would drop a good answer and buy
    /// another request.
    func test_an_unreadable_route_does_not_cost_the_country() async {
        let transport = LocalTransport()
        let exit = FakeExit()
        exit.answer = "NL"
        let interfaces = routed("utun4")
        let engine = makeEngine(alreadyUp(), transport: transport,
                                interfaces: interfaces, exit: exit)

        await refreshed(engine, on: transport) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "NL")
        }
        interfaces.primary = nil
        await refreshed(engine, on: transport) { _ in true }
        interfaces.primary = "utun4"
        await refreshed(engine, on: transport) { _ in true }

        XCTAssertEqual(exit.asks, 1,
                       "an unreadable route was read as the machine moving, and cost a request")
    }

    /// **A request that is still out when a tunnel comes up.**
    ///
    /// The tunnel coming up forces a fresh check — the one in flight was asked
    /// about the exit as it was before — and `Task.cancel()` does not make the
    /// cancelled run silent: the load throws, `regionCode()` answers nil, and
    /// its completion still arrives. Landing it would write a reading taken for
    /// a route the Mac has left, and would clear the «a request is out» flag
    /// while one is, buying a third request from the next refresh.
    func test_an_answer_that_has_been_superseded_is_not_written() async {
        let transport = LocalTransport()
        let exit = FakeExit()
        // The first ask is held open and would answer «NL»; the forced second
        // one answers «DE», which is the reading that belongs to the route.
        exit.queued = ["NL", "DE"]
        exit.holdsFirstUntilReleased = true

        let runner = FakeRunner()
        runner.listOutput =
            "* (Disconnected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        runner.statusOutput = ["work": """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun4
          }
        }
        """]
        let interfaces = routed("en0")
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, exit: exit)

        // A first reading with nothing up, so the tunnel below is seen coming
        // up rather than found already there — this test is about the forced
        // check, and `wasDown` needs a previous reading to be false about.
        await refreshed(engine, on: transport) { _ in true }

        // Now it is up and holds the route: the gate asks, and that request is
        // held open.
        runner.listOutput =
            "* (Connected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        interfaces.primary = "utun4"
        await refreshed(engine, on: transport) { $0.tunnels.count == 1 }
        await waitUntil("the first request left") { exit.asks >= 1 }

        // It drops and comes back, which forces a second check while the first
        // is still out.
        runner.listOutput =
            "* (Disconnected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        await refreshed(engine, on: transport) { $0.tunnels.isEmpty }
        runner.listOutput =
            "* (Connected) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
        let backWithACountry = await refreshed(engine, on: transport) {
            $0.tunnels.first?.exit == .throughTunnel(countryCode: "DE")
        }
        XCTAssertTrue(backWithACountry, "the second request's answer never reached the page")

        // And now the first one is let go. Its answer is older than what is on
        // the page and must be dropped rather than written over it.
        exit.release()
        // Waited for rather than raced: the assertion is that something did
        // *not* happen, and it holds trivially while the held run is still on
        // its way back. The condition is the fake's own count reaching two
        // completions — there is no count of completions, so the wait is a
        // plain one and generous.
        try? await Task.sleep(nanoseconds: 400_000_000)
        let drawn = await lastState(on: transport)?.tunnels.first?.exit
        XCTAssertEqual(drawn, .throughTunnel(countryCode: "DE"), """
        a superseded answer was written over a newer one. Cancelling a URL load         does not silence its completion, so the run that comes back last wins         unless something tells the two apart.
        """)
    }

    // MARK: - Plumbing

    /// A clock a test can move. `Date.init` cannot answer «a minute later»
    /// without the test sleeping for one.
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var _now: Date
        init(_ now: Date) { _now = now }
        var now: Date {
            get { lock.lock(); defer { lock.unlock() }; return _now }
            set { lock.lock(); _now = newValue; lock.unlock() }
        }
    }

    /// Waits for a condition the module reaches on its own thread, with a
    /// deadline so a failure is a failure rather than a hung suite.
    private func waitUntil(_ what: String, timeout: TimeInterval = 5,
                           _ condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "timed out waiting for: \(what)")
    }
}
