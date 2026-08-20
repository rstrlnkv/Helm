// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **A measurement that refused must not take the last one with it.**
///
/// Three places in this tree write the rule down and one of them is the code
/// that breaks it.
///
/// `VPNEngine.lastSpeed`: «The last measurement taken on each tunnel … **What
/// drops it is that tunnel going**, below» — and «below» is `forgetWhatIsGone`,
/// which drops the entry when the tunnel is no longer up. That is the whole
/// list of things that may drop a reading.
///
/// `HelmMeasuringSlot`, the card written for this state today: «When the run
/// ends the ink comes back, and whatever number is there then — the new one,
/// **or the old one if the tool refused** — arrives into a card brightening.»
/// The demotion to `HelmText.quiet` is *designed* around the old figure still
/// being there when the run ends, «because it is still the only reading the
/// person has».
///
/// `VPNTunnelStrip`: the button reads «Measure again» while a figure is there
/// and «Measure speed» when there is none, so the loss is visible in two places
/// at once — the tile falls back to a dash and the button forgets it has ever
/// been pressed.
///
/// What actually runs is `lastSpeed[id] = reading ?? nil`, and assigning nil to
/// a `Dictionary` subscript **removes the key**. So the ordinary ending of a run
/// on a link the tool could not characterise — the `-1009` this module's own
/// `NetworkQualitySpeed` comment measured on 2026-08-18, a tool killed at its
/// deadline, a half-written JSON `VPNSpeedReading.parse` refuses — erases the
/// figure the person was reading a second earlier.
///
/// This is «a reading older than the act» read from the other end: nothing went
/// stale, something that was still true was thrown away by an ending that had no
/// news of its own.
final class ARefusedRunKeepsTheFigureItHadTests: XCTestCase {

    private let header = "Available network connection services:"
    private let identifier = "AAAAAAAA-0000-0000-0000-000000000001"

    private func list() -> String {
        [header,
         "* (Connected) \(identifier) VPN (com.x.routed) \"routed\" [VPN:com.x.routed]"]
            .joined(separator: "\n")
    }

    private func status() -> String {
        """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun4
          }
          IsPrimaryInterface : 1
          Status : 2
        }
        """
    }

    /// One tunnel, up, carrying the default route — so the engine accepts a
    /// measurement on it rather than refusing by name. Every port named; three
    /// of the defaults reach the network or run a subprocess for twenty seconds
    /// (`NoTestTakesAProductionPortTests`).
    ///
    /// **A quiet link**, `carriesPerRead` at its default 0: with traffic on it
    /// the byte counters move between emissions and every payload differs, so a
    /// figure could survive on screen by luck of some other field having changed.
    private func oneTunnel(_ speed: FakeSpeed)
        -> (engine: VPNEngine, transport: LocalTransport) {
        let runner = FakeRunner()
        runner.listOutput = list()
        runner.statusOutput["routed"] = status()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        interfaces.counters = ["utun4": (in: 1_000_000, out: 1_000_000)]
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

    private func measure(_ transport: LocalTransport) async {
        let payload = (try? JSONEncoder().encode(VPNConnectionRef(name: "routed"))) ?? Data()
        _ = try? await transport.send(EngineCommand(name: VPNCommand.measureSpeed.rawValue,
                                                    payload: payload))
    }

    /// Waits for a state the matcher accepts, subscribing **before** the act so
    /// nothing can go by unseen.
    private func waitForState(_ transport: LocalTransport, _ what: String,
                              until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool,
                              file: StaticString = #filePath, line: UInt = #line,
                              during act: () async -> Void) async {
        let arrived = XCTestExpectation(description: what)
        let watcher = watchState(transport, until: matches, then: arrived)
        await act()
        await fulfillment(of: [arrived], timeout: 10)
        watcher.cancel()
    }

    func testARunTheToolRefusesLeavesTheLastFigureOnThePage() async {
        let taken = Date(timeIntervalSince1970: 1_700_000_000)
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 343, up: 358, rpm: 1200, at: taken, took: 19)
        let (engine, transport) = oneTunnel(speed)
        defer { speed.release(); engine.deactivate() }

        // **The precondition, and it is a real one.** An assertion that a figure
        // survived is green when no figure ever arrived, which is the default in
        // a module whose speed port has never answered.
        await waitForState(transport, "the first reading reached the page",
                           until: { $0.tunnels.first?.speed != nil },
                           during: { await measure(transport) })
        let first = await lastState(on: transport)
        XCTAssertEqual(first?.tunnels.first?.speed?.down, 343,
                       "precondition: no figure ever reached the page, so nothing below "
                       + "is about a figure being kept")
        XCTAssertEqual(first?.tunnels.first?.measuring, false,
                       "precondition: the first run has not ended, so the second cannot start")

        // A second run that the tool refuses — a `-1009`, a deadline, half a
        // JSON document. **It holds its thread**, the way the real tool holds
        // one for twenty seconds: a fake that answered instantly would be past
        // the measuring state before the wire could be read, and the two ends of
        // the run would be one event (CLAUDE.md § a fake that finishes instantly).
        speed.answer = nil
        speed.blocksUntilReleased = true
        await waitForState(transport, "the second run is in flight",
                           until: { $0.tunnels.first?.measuring == true },
                           during: { await measure(transport) })
        XCTAssertEqual(speed.askedFor.count, 2,
                       "precondition: the second run was refused by the engine rather than "
                       + "reaching the port, so this says nothing about a refusal")

        await waitForState(transport, "the second run ended",
                           until: { $0.tunnels.first?.measuring == false },
                           during: { speed.release() })

        let after = await lastState(on: transport)
        XCTAssertEqual(after?.tunnels.first?.speed?.down, 343, """
            a run the tool refused erased the reading the card was already \
            showing: `VPNEngine.lastSpeed` says the only thing that drops a \
            figure is the tunnel going, and `HelmMeasuringSlot` demotes that \
            figure to quiet ink for the length of the run precisely because it \
            is «still the only reading the person has». `lastSpeed[id] = \
            reading ?? nil` removes the key, so the tile falls back to a dash \
            and the button under it goes from «Measure again» to «Measure \
            speed» — the module forgetting it was ever asked
            """)
        XCTAssertEqual(after?.tunnels.first?.speed?.at, taken,
                       "the figure that survived is not the one that was taken")
    }
}
