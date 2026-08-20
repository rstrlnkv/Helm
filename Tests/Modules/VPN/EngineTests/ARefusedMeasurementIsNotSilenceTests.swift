// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **A refusal published through a filter that withholds duplicates is not
/// published.**
///
/// `VPNEngine.measureSpeed` refuses a name that is not the tunnel carrying the
/// default route, and its own comment says why the refusal has to reach the
/// page: «A silent return leaves the second with a spinner and no button under
/// it, a refresh over a quiet tunnel being withheld by the dedup». The repair
/// was an `emitState()` on the refusing branch — and `emitState` is the dedup.
/// Nothing about the module changed between the last emission and the refusal,
/// so the payload it builds is equal in every field to `_lastEmitted` and is
/// dropped on the floor.
///
/// The page had set `VPNViewModel.measuring = name` on the press, on purpose:
/// «a button that does nothing for a moment reads as a button that did not
/// work», cleared by the arrival that never comes. So the spinner turns on that
/// tunnel until some *other* fact about the module moves — which over a quiet
/// tunnel is nothing, and `VPNTunnelState.measuring`'s own doc calls that
/// ending «the one that shipped».
///
/// Two tunnels up with the route on one of them is not a contrived fixture: it
/// is the case `VPNTunnelChoice.primaryFirst` and the whole switcher exist for,
/// and the button under the second tunnel is the only way to reach this branch.
final class ARefusedMeasurementIsNotSilenceTests: XCTestCase {

    private let header = "Available network connection services:"

    /// Two connected rows, each with the id `--nc list` prints in front of its
    /// quoted name.
    private func list(_ named: [(id: String, name: String)]) -> String {
        ([header] + named.map {
            "* (Connected) \($0.id) VPN (com.x.\($0.name)) \"\($0.name)\" [VPN:com.x.\($0.name)]"
        }).joined(separator: "\n")
    }

    /// `scutil --nc status "<name>"` shaped as the real tool writes it — the
    /// tunnel's own `InterfaceName` inside the `IPv4` dictionary, the routing
    /// flag one level out.
    private func status(interface: String, primary: Bool) -> String {
        """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : \(interface)
          }
          IsPrimaryInterface : \(primary ? 1 : 0)
          Status : 2
        }
        """
    }

    /// Two tunnels up, the route on `routed`. Every port named — three of the
    /// defaults reach the network or run a tool for fifteen seconds
    /// (`NoTestTakesAProductionPortTests`).
    private func twoTunnels(_ speed: FakeSpeed)
        -> (engine: VPNEngine, transport: LocalTransport) {
        let runner = FakeRunner()
        runner.listOutput = list([(id: "AAAAAAAA-0000-0000-0000-000000000001", name: "routed"),
                                  (id: "BBBBBBBB-0000-0000-0000-000000000002", name: "beside")])
        runner.statusOutput["routed"] = status(interface: "utun4", primary: true)
        runner.statusOutput["beside"] = status(interface: "utun9", primary: false)
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        // **A quiet tunnel, which is the case the dedup bites on.** `carriesPerRead`
        // is 0, so the counters answer the same pair at every reading — a Mac
        // where nothing is moving through either tunnel while the button is
        // pressed. With traffic on the link the counters cross a kilobyte, the
        // payload differs and the refusal reaches the page *by accident*, which
        // is the green-by-luck this fixture refuses.
        interfaces.counters = ["utun4": (in: 1_000_000, out: 1_000_000),
                               "utun9": (in: 2_000_000, out: 2_000_000)]
        // **The exit request is still out**, which is what the real port is for
        // up to eight seconds of every refresh that starts one. It is also what
        // keeps this test's reading of the wire deterministic: the check's own
        // completion calls `emitState` too, and under `VPNWorkQueue.inline` that
        // runs on the answering task's thread rather than on the module's serial
        // queue — so the two emissions race and one is silently swallowed as a
        // duplicate (`TheTestQueueIsAsSerialAsTheRealOneTests`).
        let exit = FakeExit()
        exit.hangs = true
        let transport = LocalTransport()
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, apps: FakeApps(), transport: transport,
                               interfaces: interfaces, exit: exit, speed: speed,
                               work: .inline)
        engine.refresh()
        return (engine, transport)
    }

    private func measure(_ transport: LocalTransport, _ name: String) async {
        let payload = (try? JSONEncoder().encode(VPNConnectionRef(name: name))) ?? Data()
        _ = try? await transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue,
                                                    payload: payload))
    }

    /// **The control.** The same command, on the tunnel that does carry the
    /// route, reaches the page — so the silence below belongs to the refusal and
    /// not to a command that never arrived.
    ///
    /// The fake blocks until released, the way `networkQuality` holds its thread
    /// for fifteen seconds: a port that answered instantly would be past the
    /// state this asserts on before the assertion was reached.
    func testAMeasurementTheEngineAcceptsIsAnnouncedAsItStarts() async {
        let speed = FakeSpeed()
        speed.blocksUntilReleased = true
        let running = XCTestExpectation(description: "the run has started")
        speed.onStart = { running.fulfill() }
        let (engine, transport) = twoTunnels(speed)
        defer { speed.release(); engine.deactivate() }

        let seen = await stateEvents(on: transport) { await measure(transport, "routed") }
        await fulfillment(of: [running], timeout: 5)

        XCTAssertTrue(seen.contains { $0?.tunnels.contains { $0.measuring } == true }, """
            the accepted measurement never reached the wire, so this file's \
            fixture cannot say anything about the refusal below
            """)
    }

    /// **The finding.** The refusal changes no other field, so the payload it
    /// publishes is a duplicate and never leaves the engine.
    ///
    /// Counted rather than matched on content: a fix emits the same fields — what
    /// is wrong today is that nothing arrives at all, and the page is left
    /// holding the optimistic flag it set on the press. The replayed event is the
    /// first of the count, and the precondition below establishes that there is
    /// exactly one of those before the press.
    func testAMeasurementRefusedOverAQuietTunnelStillReachesThePage() async {
        let speed = FakeSpeed()
        let (engine, transport) = twoTunnels(speed)
        defer { engine.deactivate() }

        let quiet = await stateEvents(on: transport)
        XCTAssertEqual(quiet.count, 1,
                       "precondition: the wire is not settled, so a count means nothing")
        XCTAssertEqual(quiet.last??.tunnels.count, 2,
                       "precondition: both tunnels never reached the page")
        XCTAssertEqual(quiet.last??.tunnels.first(where: { $0.name == "beside" })?.exit,
                       .besideTunnel,
                       "precondition: «beside» carries the route, so nothing is refused")

        let seen = await stateEvents(on: transport) { await measure(transport, "beside") }

        XCTAssertTrue(speed.askedFor.isEmpty,
                      "precondition: the run was started rather than refused")
        XCTAssertGreaterThan(seen.count, 1, """
            the engine refused to measure a tunnel that is not carrying the \
            traffic and said so to nobody: the payload it published was equal in \
            every field to the last one, so `emitState` withheld it as a \
            duplicate — and the page, which sets its own spinner on the press, \
            has nothing to clear it with
            """)
    }
}
