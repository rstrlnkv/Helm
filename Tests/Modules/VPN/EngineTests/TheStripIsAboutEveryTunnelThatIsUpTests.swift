// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **Two tunnels up, and the second was drawn nowhere.**
///
/// The payload carried one `VPNTunnelState` — the tunnel holding the default
/// route, or the first that was up — so a Mac with a work tunnel and a home
/// tunnel had one of them on the page and no way to reach the other. It carries
/// every connected tunnel that has an interface reading now, ordered so that
/// «the first» means the one the traffic actually leaves through.
///
/// And the thing that ordering is *for*: a measurement cannot be taken for a
/// tunnel that is not carrying the default route. `networkQuality` cannot be
/// bound to an interface on this build of macOS — `-I utunN` prints
/// `error_code -1009` at exit status 0 — so an unbound run follows the default
/// route whatever the switcher is showing. Offering it on a non-routed tunnel
/// would file one tunnel's figure under another's name, and the refusal is here
/// in the engine rather than only in the view because the view is not the only
/// thing that can send a command.
final class TheStripIsAboutEveryTunnelThatIsUpTests: XCTestCase {

    private let at = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    /// Two configurations, in the order `scutil --nc list` hands them over.
    private func list(_ first: String, _ second: String) -> String {
        """
        * (\(first)) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) "work" [VPN:com.x.work]
        * (\(second)) 22222222-2222-2222-2222-222222222222 VPN (com.x.home) "home" [VPN:com.x.home]
        """
    }

    private func statusNaming(_ interface: String) -> String {
        """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : \(interface)
          }
        }
        """
    }

    /// Both tunnels up, each on its own `utunN`, with the default route on
    /// whichever is named.
    private func bothUp(routed: String?) -> (FakeRunner, FakeInterfaces) {
        let runner = FakeRunner()
        runner.listOutput = list("Connected", "Connected")
        runner.statusOutput = ["work": statusNaming("utun4"), "home": statusNaming("utun7")]
        let interfaces = FakeInterfaces()
        interfaces.primary = routed
        interfaces.counters = ["utun4": (in: 4_000, out: 2_000),
                               "utun7": (in: 9_000, out: 3_000)]
        return (runner, interfaces)
    }

    private func makeEngine(_ runner: FakeRunner, transport: LocalTransport,
                            interfaces: FakeInterfaces, speed: FakeSpeed = FakeSpeed(),
                            exit: FakeExit = FakeExit()) -> VPNEngine {
        VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                  transport: transport, interfaces: interfaces, exit: exit, speed: speed,
                  work: .inline)
    }

    private func measure(_ engine: VPNEngine, _ name: String) async throws {
        let payload = try JSONEncoder().encode(VPNConnectionRef(name: name))
        _ = try await engine.transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue,
                                                          payload: payload))
    }

    // MARK: - Both of them reach the page

    func test_two_tunnels_up_both_reach_the_page() async {
        let (runner, interfaces) = bothUp(routed: "utun7")
        let transport = LocalTransport()
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        engine.refresh()

        let tunnels = await lastState(on: transport)?.tunnels ?? []
        XCTAssertEqual(tunnels.count, 2, """
            \(tunnels.count) tunnel(s) on the wire with two up: the second is \
            drawn nowhere and cannot be reached from the page at all
            """)
        XCTAssertEqual(Set(tunnels.map(\.interface)), ["utun4", "utun7"])
    }

    /// The order is the promise «the first» rests on, and the page opens on the
    /// first: the default-route tunnel leads, and the rest keep the tool's order.
    func test_the_tunnel_carrying_the_traffic_is_first_on_the_wire() async {
        let (runner, interfaces) = bothUp(routed: "utun7")   // «home», the tool's second
        let transport = LocalTransport()
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        engine.refresh()

        let tunnels = await lastState(on: transport)?.tunnels ?? []
        XCTAssertEqual(tunnels.map(\.name), ["home", "work"], """
            the page opens on «\(tunnels.first?.name ?? "nothing")» while the \
            traffic leaves through «home» — and a selection that goes stale falls \
            back to that same first entry
            """)
    }

    /// A tunnel the tool has not named an interface for is not on the wire: the
    /// strip's every reading is about an interface, and a segment for a tunnel
    /// with none is a segment leading to an empty card.
    func test_a_tunnel_with_no_interface_reading_yet_is_not_offered() async {
        let (runner, interfaces) = bothUp(routed: "utun4")
        runner.statusOutput = ["work": statusNaming("utun4")]   // «home» is still coming up
        let transport = LocalTransport()
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        engine.refresh()

        let named = await lastState(on: transport)?.tunnels.map(\.name)
        XCTAssertEqual(named, ["work"])
    }

    // MARK: - The refusal

    /// **The one rule this whole change turns on.** A run for «work» while the
    /// route is on «home» would measure «home» and file the figure under
    /// «work» — so it never starts, and no subprocess is spent finding that out.
    func test_a_measurement_on_a_tunnel_that_is_not_routed_starts_nothing() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")      // the route is on «home»
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, speed: speed)
        engine.refresh()
        let count = await lastState(on: transport)?.tunnels.count
        XCTAssertEqual(count, 2,
                       "precondition: there is no second tunnel to refuse a measurement for")

        try await measure(engine, "work")

        XCTAssertTrue(speed.askedFor.isEmpty, """
            fifteen seconds of somebody's traffic were spent measuring the route \
            — which is «home» — and the figure would have been drawn under «work»
            """)
    }

    /// And the tunnel that *does* hold the route is measured, so the refusal
    /// above is a refusal rather than a measurement that never works.
    func test_the_routed_tunnel_is_measured() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, speed: speed)
        engine.refresh()

        let landed = expectation(description: "the reading reached the page")
        let watcher = watchState(transport,
                                 until: { $0.tunnels.contains { $0.speed != nil } },
                                 then: landed)
        try await measure(engine, "home")

        await fulfillment(of: [landed], timeout: 5)
        watcher.cancel()
        XCTAssertEqual(speed.askedFor, [nil], "one run, and unbound")
    }

    /// **A refusal sets no flag.** The refusal happens before the run's own
    /// state is written, so no tunnel comes back saying a measurement is in
    /// flight for it — which is what a spinner is drawn from, and what would
    /// turn for ever if the flag were set and then never cleared.
    ///
    /// Asserted on the flag rather than on «a payload was emitted»: the refusal
    /// leaves every field of the state as it was, so `emitState` withholds it as
    /// a duplicate — and the transport replays its last event to every new
    /// subscriber, so counting arrivals here would pass with the whole refusal
    /// deleted. The page never puts a spinner up for this case in any event: the
    /// button it would come from is not drawn on a tunnel that is not routed.
    func test_a_refused_measurement_leaves_no_run_in_flight() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        speed.blocksUntilReleased = true       // a run that started would still be going
        defer { speed.release() }
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, speed: speed)
        engine.refresh()

        try await measure(engine, "work")

        let tunnels = await lastState(on: transport)?.tunnels ?? []
        XCTAssertEqual(tunnels.count, 2, "precondition: the state never reached the page")
        XCTAssertTrue(tunnels.allSatisfy { !$0.measuring }, """
            the engine marked a run in flight for a tunnel it then refused to \
            measure — nothing ends that run, so the mark never comes off
            """)
    }

    /// A command naming a tunnel that is not there at all — a stale press, a
    /// name that was renamed in System Settings — is the same refusal.
    func test_a_measurement_for_a_tunnel_nobody_has_is_refused() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 1, up: 1, rpm: 1, at: at)
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, speed: speed)
        engine.refresh()

        try await measure(engine, "a tunnel nobody has")

        XCTAssertTrue(speed.askedFor.isEmpty)
    }

    // MARK: - Whose run it is

    /// **The flag was already per tunnel on the wire and could not be honest.**
    /// One `Bool` in the engine meant every tunnel in the list would say it was
    /// measuring; the engine holds the *name* now, so exactly one does.
    func test_only_the_measured_tunnels_flag_is_set() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        speed.blocksUntilReleased = true
        defer { speed.release() }
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                               transport: transport, interfaces: interfaces,
                               exit: FakeExit(), speed: speed, work: .background)

        let ready = expectation(description: "both tunnels are on the wire")
        let first = watchState(transport, until: { $0.tunnels.count == 2 }, then: ready)
        engine.refresh()
        await fulfillment(of: [ready], timeout: 5)
        first.cancel()

        let running = expectation(description: "the page was told a run is in flight")
        let watcher = watchState(transport,
                                 until: { $0.tunnels.contains(where: \.measuring) },
                                 then: running)
        try await measure(engine, "home")
        await fulfillment(of: [running], timeout: 5)
        watcher.cancel()

        let tunnels = await lastState(on: transport)?.tunnels ?? []
        XCTAssertEqual(tunnels.filter(\.measuring).map(\.name), ["home"], """
            \(tunnels.filter(\.measuring).count) of \(tunnels.count) tunnels say a \
            measurement is in flight for them, and one run is going: a spinner is \
            turning over a tunnel nobody is measuring
            """)
    }

    // MARK: - A figure belongs to the tunnel it was taken on

    /// **The figure stays with its tunnel when the route moves.** It was taken
    /// while that tunnel held the route, so it is that tunnel's own reading —
    /// and it carries its age on the screen once it is older than
    /// `VPNTunnelFacts.speedGoesStaleAfter`. Dropping it on a route change would
    /// throw away a correctly attributed number; what does drop it is the tunnel
    /// going, which is where the reading stops being about anything.
    func test_a_figure_stays_with_its_tunnel_when_the_route_moves() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")      // «home» holds the route
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, speed: speed)
        engine.refresh()
        let landed = expectation(description: "the reading reached the page")
        let watcher = watchState(transport,
                                 until: { $0.tunnels.contains { $0.speed != nil } },
                                 then: landed)
        try await measure(engine, "home")
        await fulfillment(of: [landed], timeout: 5)
        watcher.cancel()

        interfaces.primary = "utun4"                            // the route moves to «work»
        engine.refresh()

        let tunnels = await lastState(on: transport)?.tunnels ?? []
        XCTAssertEqual(tunnels.first(where: { $0.name == "home" })?.speed?.down, 240, """
            «home»'s own measurement was thrown away because the route moved to \
            another tunnel — it was taken while «home» held the route and is \
            still «home»'s figure, with its age under it
            """)
        XCTAssertNil(tunnels.first(where: { $0.name == "work" })?.speed, """
            «work» is drawing a figure measured on «home»: the run follows the \
            route and the reading belongs to whoever held it
            """)
    }

    /// And a tunnel that goes takes its figure with it, so the next tunnel
    /// raised under the same name never inherits one.
    func test_a_tunnel_that_goes_takes_its_figure_with_it() async throws {
        let (runner, interfaces) = bothUp(routed: "utun7")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, speed: speed)
        engine.refresh()
        let landed = expectation(description: "the reading reached the page")
        let watcher = watchState(transport,
                                 until: { $0.tunnels.contains { $0.speed != nil } },
                                 then: landed)
        try await measure(engine, "home")
        await fulfillment(of: [landed], timeout: 5)
        watcher.cancel()

        runner.listOutput = list("Connected", "Disconnected")
        engine.refresh()
        runner.listOutput = list("Connected", "Connected")
        engine.refresh()

        let home = await lastState(on: transport)?.tunnels.first { $0.name == "home" }
        XCTAssertNotNil(home, "precondition: «home» never came back, so nothing was inherited")
        XCTAssertNil(home?.speed, """
            the tunnel that came up is drawing the figure of the one that went — \
            macOS raises the next one on a new utunN, and its throughput is not \
            its predecessor's
            """)
    }

    // MARK: - A document written before this change

    /// **A stored default does not make an older document decode**, which is why
    /// this payload has a hand-written decoder at all: Swift's synthesised
    /// `Decodable` wants the key whatever the property's initial value is, and
    /// `JSONDecoder` then gives up on the whole document — every connection the
    /// page draws, for the sake of one field.
    func test_a_payload_written_before_the_switcher_still_draws_its_tunnel() throws {
        let old = """
        {
          "connections": [{"id": "1", "name": "work", "status": "connected", "kind": "IKEv2"}],
          "autoConnected": [],
          "facts": {
            "name": "work", "interface": "utun4",
            "bytesIn": 4000, "bytesOut": 2000,
            "exit": {"besideTunnel": {}}
          }
        }
        """
        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self,
                                               from: Data(old.utf8))
        XCTAssertEqual(payload.tunnels.map(\.name), ["work"], """
            a payload written by the build before this one lost its tunnel — the \
            old key is read into a one-element list, or the strip is empty at \
            every first launch after an update
            """)
        XCTAssertEqual(payload.connections.count, 1,
                       "the whole document was refused for the sake of one renamed key")
    }

    /// A document from a build older still — before the strip existed — has
    /// neither key, and is not a throw either.
    func test_a_payload_from_before_the_strip_decodes_with_no_tunnels() throws {
        let older = """
        {"connections": [], "autoConnected": []}
        """
        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self,
                                               from: Data(older.utf8))
        XCTAssertEqual(payload.tunnels, [])
    }
}
