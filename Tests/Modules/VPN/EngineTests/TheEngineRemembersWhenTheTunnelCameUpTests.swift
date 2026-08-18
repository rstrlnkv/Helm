// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// What the tile strip is told: which tunnel carries the traffic, since when,
/// what it has carried, and where it leaves from.
///
/// **The moment a tunnel came up is a thing only Helm can know, and only if it
/// was watching.** `scutil` does not report it — the list says `Connected` and
/// nothing else — so the stamp is Helm's own observation of a service that was
/// down at the last reading and is up at this one. A tunnel already up when the
/// process started was seen coming up by nobody, and stamping it there would be
/// Helm timing its own launch and calling it the tunnel's age.
final class TheEngineRemembersWhenTheTunnelCameUpTests: XCTestCase {

    private let uuid = "11111111-1111-1111-1111-111111111111"
    private let other = "22222222-2222-2222-2222-222222222222"
    private let at = Date(timeIntervalSince1970: 1_700_000_000)

    private func list(_ status: String, _ name: String = "A", id: String? = nil) -> String {
        "(\(status)) \(id ?? uuid) IPSec \"\(name)\""
    }

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn",
                                           backing: InMemoryKeyValueStore()))
    }

    /// Every port named, including the three this feature added: their
    /// production defaults reach the network and a subprocess that runs for
    /// fifteen seconds, and a construction that forgets one of them is an
    /// integration test nobody asked for (CLAUDE.md § a default argument naming
    /// a real port).
    private func makeEngine(_ runner: FakeRunner,
                            transport: LocalTransport,
                            interfaces: FakeInterfaces,
                            exit: FakeExit = FakeExit(),
                            speed: FakeSpeed = FakeSpeed()) -> VPNEngine {
        // The tool's answer about the one tunnel these tests raise. Which
        // interface a tunnel is on is asked of `scutil --nc status <name>` now,
        // not of the dynamic store by service id — the two identifier spaces are
        // not the same for a NetworkExtension tunnel, and the strip was absent
        // on every Mac for exactly that reason (`VPNStatusParser`). A test that
        // needs another answer sets `statusOutput` itself.
        if runner.statusOutput["A"] == nil { runner.statusOutput["A"] = statusNaming("utun4") }
        let at = at
        return VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                         transport: transport, interfaces: interfaces, exit: exit,
                         speed: speed, now: { at }, work: .inline)
    }

    /// A tunnel that is up on `utun4`, with the Mac's default route through it.
    private func tunnelIsTheDefaultRoute() -> FakeInterfaces {
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        interfaces.counters = ["utun4": (in: 1_000_000, out: 500_000)]
        return interfaces
    }

    /// What `scutil --nc status "<name>"` prints for a tunnel that is up on this
    /// interface — the shape of the real thing, trimmed to the two lines the
    /// parser reads. `TheInterfaceComesFromTheToolTests` carries the whole
    /// captured output, decoys and all.
    private func statusNaming(_ interface: String, primary: Bool = true) -> String {
        """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : \(interface)
          }
          IsPrimaryInterface : \(primary ? 1 : 0)
        }
        """
    }

    // MARK: - Since when

    func test_a_tunnel_already_up_at_the_first_reading_carries_no_stamp() async {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let engine = makeEngine(runner, transport: transport,
                                interfaces: tunnelIsTheDefaultRoute())

        engine.refresh()

        let facts = await lastState(on: transport)?.facts
        XCTAssertNotNil(facts, "the strip is about a tunnel that is up, and this one is")
        XCTAssertNil(facts?.since,
                     "Helm was launched after this tunnel came up and stamped it anyway — "
                     + "the uptime on screen is then the age of the app, not of the tunnel")
    }

    func test_a_tunnel_that_comes_up_between_two_readings_is_stamped() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let transport = LocalTransport()
        let engine = makeEngine(runner, transport: transport,
                                interfaces: tunnelIsTheDefaultRoute())

        engine.refresh()                     // seen down
        runner.listOutput = list("Connected")
        engine.refresh()                     // and now up

        let facts = await lastState(on: transport)?.facts
        XCTAssertEqual(facts?.since, at,
                       "the one moment Helm can honestly report is the one it watched")
    }

    /// And the stamp dies with its tunnel: a service that falls and comes back
    /// is a new tunnel, on a new `utunN`, and reading the old stamp against it
    /// would report an uptime that spans the gap.
    func test_a_stamp_does_not_outlive_the_tunnel_it_belongs_to() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let transport = LocalTransport()
        let interfaces = tunnelIsTheDefaultRoute()
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        engine.refresh()
        runner.listOutput = list("Connected")
        engine.refresh()                     // stamped
        runner.listOutput = list("Disconnected")
        engine.refresh()                     // and dropped

        let facts = await lastState(on: transport)?.facts
        XCTAssertNil(facts, "nothing is up, so there is no tunnel to draw a strip about")
    }

    // MARK: - Which tunnel

    /// Two tunnels up is an ordinary Mac. The strip is about the one the person
    /// is on the internet through, which is the only one «this tunnel» can
    /// honestly mean.
    func test_the_strip_is_about_the_tunnel_carrying_the_default_route() async {
        let runner = FakeRunner()
        runner.listOutput = list("Connected", "Split", id: uuid) + "\n"
            + list("Connected", "Full", id: other)
        let transport = LocalTransport()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun5"
        interfaces.counters = ["utun4": (in: 1, out: 1), "utun5": (in: 2_000, out: 3_000)]
        runner.statusOutput = ["Split": statusNaming("utun4", primary: false),
                               "Full": statusNaming("utun5")]
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        engine.refresh()

        let facts = await lastState(on: transport)?.facts
        XCTAssertEqual(facts?.name, "Full")
        XCTAssertEqual(facts?.interface, "utun5")
        XCTAssertEqual(facts?.bytesIn, 2_000, "the counters are the named tunnel's own")
    }

    // MARK: - Where the traffic leaves

    /// Routing alone answers this one: the tunnel is up, the default route is
    /// the Wi-Fi, and nobody had to be asked where the Mac appears to be.
    func test_a_tunnel_beside_the_default_route_needs_no_request_to_be_reported() async {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let interfaces = tunnelIsTheDefaultRoute()
        interfaces.primary = "en0"
        let exit = FakeExit()
        exit.answer = nil
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces, exit: exit)

        engine.refresh()

        let facts = await lastState(on: transport)?.facts
        XCTAssertEqual(facts?.exit, .besideTunnel,
                       "the tunnel is up and the traffic is going round it — the one state "
                       + "this check exists for")
    }

    /// And when the tunnel does carry the route, the country the exit answered
    /// reaches the page. Awaited on the payload rather than on a number of
    /// yields: the request is asynchronous, and a fixed count of yields asserts
    /// on whichever half of the work had finished.
    func test_the_country_reaches_the_page_when_the_exit_answers() async {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let transport = LocalTransport()
        let exit = FakeExit()
        exit.answer = "NL"
        let engine = makeEngine(runner, transport: transport,
                                interfaces: tunnelIsTheDefaultRoute(), exit: exit)

        let arrived = expectation(description: "the country reached the page")
        let watcher = watchState(transport,
                                 until: { $0.facts?.exit == .throughTunnel(countryCode: "NL") },
                                 then: arrived)
        engine.refresh()
        runner.listOutput = list("Connected")
        engine.refresh()                     // came up: the answer is news

        await fulfillment(of: [arrived], timeout: 5)
        watcher.cancel()
    }

    // MARK: - The measurement

    /// **The run is not bound to the tunnel's interface, and that is the honest
    /// reading rather than a workaround.** Measured on this machine while this
    /// was written: `networkQuality -I utunN` against a real tunnel prints
    /// `"error_code": -1009` with exit status 0 and no throughput at all, while
    /// the same tool unbound answers normally — binding a socket to a
    /// point-to-point tun does not work here. The strip exists only for the
    /// tunnel carrying the default route, so an unbound measurement follows that
    /// route and *is* that tunnel's figure whenever the strip is on screen.
    ///
    /// The port keeps its `onInterface:` all the same — it is the seam a build
    /// with a working bind goes through — and the fake records what it was
    /// handed, so «this run was not bound» is a fact rather than a hope.
    func test_a_measurement_is_unbound_and_lands_in_the_payload() async throws {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        let reading = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        speed.answer = reading
        let engine = makeEngine(runner, transport: transport,
                                interfaces: tunnelIsTheDefaultRoute(), speed: speed)
        engine.refresh()
        // The run happens off the module's queue now, so the figure arrives when
        // it arrives: awaited on the payload, never on a count of yields.
        let landed = expectation(description: "the reading reached the page")
        let watcher = watchState(transport, until: { $0.facts?.speed == reading }, then: landed)

        _ = try await engine.transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue))

        await fulfillment(of: [landed], timeout: 5)
        watcher.cancel()
        XCTAssertEqual(speed.askedFor, [nil],
                       "one run, and unbound: `networkQuality -I utunN` answers -1009 and no "
                       + "throughput at all on this build of macOS")
    }

    /// **The measurement must not hold the module's one serial queue.**
    ///
    /// `VPNWorkQueue` is serial and every connect, disconnect and poll passes
    /// through it; `networkQuality` blocks its thread for fifteen seconds by
    /// design and up to sixty at its deadline. Run there, a person pressing
    /// Connect while the tile is measuring waits for the tool — the module is
    /// simply deaf for the length of a measurement. So: off the queue **and**
    /// off the cooperative pool, back on the queue for the state write.
    ///
    /// This is the one test in the file that runs `.background`, because with
    /// `.inline` the work queue is the caller's own thread and there is no queue
    /// to block.
    func test_a_connect_is_answered_while_a_measurement_is_in_flight() async throws {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 240, up: 40, rpm: 300, at: at)
        speed.blocksUntilReleased = true
        defer { speed.release() }
        let measuring = expectation(description: "the run has started and is holding a thread")
        speed.onStart = { measuring.fulfill() }
        let answered = expectation(description: "the connect reached the tool")
        runner.onRun = { args in if args == ["--nc", "start", "A"] { answered.fulfill() } }
        runner.statusOutput = ["A": statusNaming("utun4")]
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                               transport: transport, interfaces: tunnelIsTheDefaultRoute(),
                               exit: FakeExit(), speed: speed, work: .background)
        let ready = expectation(description: "the engine has read the list once")
        let watcher = watchState(transport, until: { $0.facts != nil }, then: ready)
        engine.refresh()
        await fulfillment(of: [ready], timeout: 5)
        watcher.cancel()

        _ = try await engine.transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue))
        await fulfillment(of: [measuring], timeout: 5)
        engine.connect("A")

        await fulfillment(of: [answered], timeout: 5)
    }

    /// Nothing up is nothing to measure: the tool runs for fifteen seconds and
    /// reaches the network, and a strip nobody is drawing has no use for it.
    func test_nothing_up_is_not_measured() async throws {
        let runner = FakeRunner()
        runner.listOutput = list("Disconnected")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 1, up: 1, rpm: 1, at: at)
        let engine = makeEngine(runner, transport: transport,
                                interfaces: tunnelIsTheDefaultRoute(), speed: speed)
        engine.refresh()

        _ = try await engine.transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue))

        XCTAssertTrue(speed.askedFor.isEmpty)
    }

    /// **A press that lands after the tunnel went measures nothing.**
    ///
    /// The press sets the page's flag optimistically, because the command has a
    /// queue to cross, and by the time it gets there the tunnel can be gone. Two
    /// things must then be true: no fifteen-second subprocess is started for a
    /// tunnel that is not there, and the page is not left holding a strip with a
    /// spinner in it and no button to press again. The refresh that noticed the
    /// drop publishes the second — the interface a tunnel is on is cached and
    /// dropped by that same refresh — and `measureSpeed` publishes on its own
    /// early return as well, the way `connectNow` does, for the paths that reach
    /// it without one.
    func test_a_press_after_the_tunnel_went_measures_nothing() async throws {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 1, up: 1, rpm: 1, at: at)
        let engine = makeEngine(runner, transport: transport,
                                interfaces: tunnelIsTheDefaultRoute(), speed: speed)
        engine.refresh()
        let onScreen = await lastState(on: transport)?.facts
        XCTAssertNotNil(onScreen, "precondition: the strip was never on screen, so the press "
                        + "this test is about could not have been made")

        // The tunnel goes, and the network watcher's refresh notices — which is
        // what happens in the app, and what the press is racing.
        runner.listOutput = list("Disconnected")
        engine.refresh()
        _ = try await engine.transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue))

        XCTAssertTrue(speed.askedFor.isEmpty,
                      "fifteen seconds of somebody's traffic spent measuring a tunnel that "
                      + "is not there")
        let after = await lastState(on: transport)?.facts
        XCTAssertNil(after, "the page keeps a strip for a tunnel that has gone")
    }

    /// **The dedup could strand the spinner, and this is why «measuring» is on
    /// the wire rather than in the page's head.**
    ///
    /// A payload equal in every field to the last one sent is withheld — which
    /// is what stops a night of polling re-rendering every page. Now take the
    /// worst ending a first measurement can have: the tool refuses (`-1009` at
    /// exit 0, or killed at its deadline), so `speed` was nil and stays nil, and
    /// over a quiet tunnel the counters have not moved a kilobyte in those
    /// fifteen seconds either. Every field the same, nothing emitted, and a page
    /// whose spinner is cleared by the *arrival* of a state turns until the app
    /// is restarted. A refresh does not rescue it: it goes through the same
    /// dedup.
    ///
    /// With the run's own state in the payload the two ends of a run are
    /// changes, so they are never withheld — the engine says «measuring» and
    /// then «not measuring» itself, and no page has to infer it from a press it
    /// may not even have been there for.
    func test_a_refused_run_over_a_quiet_tunnel_still_says_it_has_stopped() async throws {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let interfaces = tunnelIsTheDefaultRoute()
        interfaces.carriesPerRead = 0            // a tunnel with nothing on it
        let speed = FakeSpeed()
        speed.answer = nil                       // the tool refused
        speed.blocksUntilReleased = true
        defer { speed.release() }
        runner.statusOutput = ["A": statusNaming("utun4")]
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(),
                               transport: transport, interfaces: interfaces,
                               exit: FakeExit(), speed: speed, work: .background)

        let ready = expectation(description: "the engine has read the list once")
        let first = watchState(transport, until: { $0.facts != nil }, then: ready)
        engine.refresh()
        await fulfillment(of: [ready], timeout: 5)
        first.cancel()

        let started = expectation(description: "the page was told a run is in flight")
        let running = watchState(transport, until: { $0.facts?.measuring == true }, then: started)
        _ = try await engine.transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue))
        await fulfillment(of: [started], timeout: 5)
        running.cancel()

        // Registered before the run is let go, and the replayed last payload
        // says «measuring», so nothing here can be satisfied by the state that
        // is already on the wire.
        let stopped = expectation(description: "the page was told the run has ended")
        let ended = watchState(transport, until: { $0.facts?.measuring == false }, then: stopped)
        speed.release()

        await fulfillment(of: [stopped], timeout: 5)
        ended.cancel()
        let facts = await lastState(on: transport)?.facts
        XCTAssertNil(facts?.speed, "precondition: this is the run that answered nothing")
    }

    // MARK: - What the counters cost the page

    /// **The decision about the churn these counters would otherwise cause.**
    ///
    /// The payload is withheld only when it is equal in every field to the last
    /// one sent, and a byte counter moves on its own — so a raw count makes
    /// every re-read news. The count goes on the wire in whole kilobytes
    /// (`VPNInterfaceCounters.onTheWire`), which is the granularity the strip is
    /// drawn at, and this is the measurement: a connect over a live tunnel polls
    /// 26 times, each read finding another packet carried.
    func test_a_poll_over_a_live_tunnel_is_not_a_re_render_for_every_packet() async {
        let runner = FakeRunner()
        // One tunnel up and carrying the traffic, and a second the person has
        // just asked for that never comes up: the poll behind it re-reads 26
        // times, and each of those readings finds the live tunnel a packet older.
        runner.listOutput = list("Connected", "Full", id: other) + "\n" + list("Disconnected")
        let transport = LocalTransport()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun5"
        interfaces.counters = ["utun5": (in: 2_000, out: 2_000)]
        runner.statusOutput = ["Full": statusNaming("utun5")]
        interfaces.carriesPerRead = 40          // a keepalive between two readings
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        let events = await stateEvents(on: transport) {
            engine.refresh()                    // the page's baseline
            engine.connect("A")                 // accepted; the poll re-reads 26 times
        }

        XCTAssertGreaterThan(runner.listReadCount, 25,
                             "precondition: the poll did run its 26 reads — without them "
                             + "this test would pass against an engine that never polls")
        XCTAssertLessThan(events.count, 5,
                          "\(events.count) state events behind one connect: the raw byte counter is "
                          + "on the wire, so every one of the poll's 26 re-reads re-rendered "
                          + "every mounted page for a figure no screen can draw")
    }

    /// The other half, without which the first is a strip that has gone still: a
    /// kilobyte is a figure the screen can draw, and it goes out.
    func test_a_kilobyte_carried_is_news_and_a_packet_is_not() async {
        let runner = FakeRunner()
        runner.listOutput = list("Connected")
        let transport = LocalTransport()
        let interfaces = tunnelIsTheDefaultRoute()
        let engine = makeEngine(runner, transport: transport, interfaces: interfaces)

        let events = await stateEvents(on: transport) {
            engine.refresh()                                          // baseline
            interfaces.counters = ["utun4": (in: 1_000_400, out: 500_000)]
            engine.refresh()                                          // under a kilobyte
            interfaces.counters = ["utun4": (in: 1_002_000, out: 500_000)]
            engine.refresh()                                          // two kilobytes
        }

        XCTAssertEqual(events.count, 2,
                       "three readings over two drawable states must say exactly two things")
    }

    // MARK: - The wire

    /// A state event from a build that predates the field still decodes. A throw
    /// here would cost the page every connection it draws for the sake of one
    /// field (CLAUDE.md § a `defaulted` property on a `Codable` payload).
    func test_a_state_payload_without_the_tunnel_still_decodes() throws {
        let legacy = Data("""
        {"connections":[],"autoConnected":[],"defaultName":null}
        """.utf8)

        let payload = try JSONDecoder().decode(VPNEngine.StatePayload.self, from: legacy)

        XCTAssertNil(payload.facts)
    }
}
