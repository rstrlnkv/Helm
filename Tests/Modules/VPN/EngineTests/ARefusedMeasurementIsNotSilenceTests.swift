// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import XCTest
@testable import Module_VPN_Engine

/// **A refusal published through a filter that withholds duplicates is not
/// published.**
///
/// `VPNEngine.measureSpeed` refuses a name that is not the tunnel carrying the
/// default route, and the refusal must reach the page, which set
/// `VPNViewModel.measuring` on the press and clears it on the next arrival. The
/// refusal changes no field, so `emitState`'s dedup would withhold it and the
/// spinner would turn over a quiet tunnel until something else moved; the
/// refusing branch forces the emission. Two tunnels up with the route on one is
/// the case `VPNTunnelChoice.primaryFirst` and the switcher exist for.
final class ARefusedMeasurementIsNotSilenceTests: XCTestCase {

    private let header = "Available network connection services:"

    /// Two connected rows, each with the id `--nc list` prints in front of its
    /// quoted name.
    private func list(_ named: [(id: String, name: String)]) -> String {
        ([header] + named.map {
            "* (Connected) \($0.id) VPN (com.x.\($0.name)) \"\($0.name)\" [VPN:com.x.\($0.name)]"
        }).joined(separator: "\n")
    }

    /// Two tunnels up, the route on `routed`. Every port named
    /// (`NoTestTakesAProductionPortTests`).
    private func twoTunnels(_ speed: FakeSpeed)
        -> (engine: VPNEngine, news: EngineNews<VPNEngine.StatePayload>) {
        let runner = FakeRunner()
        runner.listOutput = list([(id: "AAAAAAAA-0000-0000-0000-000000000001", name: "routed"),
                                  (id: "BBBBBBBB-0000-0000-0000-000000000002", name: "beside")])
        runner.statusOutput["routed"] = scutilStatus("utun4", primary: true, extra: ["Status : 2"])
        runner.statusOutput["beside"] = scutilStatus("utun9", primary: false, extra: ["Status : 2"])
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        // **A quiet tunnel, the case the dedup bites on.** Counters that moved
        // would make the payload differ and the refusal reach the page by luck.
        interfaces.counters = ["utun4": (in: 1_000_000, out: 1_000_000),
                               "utun9": (in: 2_000_000, out: 2_000_000)]
        // **The exit request is still out**, as the real port's is for seconds of
        // every refresh. Its completion calls `emitState` too, and under
        // `VPNWorkQueue.inline` that runs off the module's serial queue, so an
        // answered check would race this test's emission
        // (`TheTestQueueIsAsSerialAsTheRealOneTests`).
        let exit = FakeExit()
        exit.hangs = true
        let news = EngineNews<VPNEngine.StatePayload>()
        let engine = VPNEngine(settings: VPNSettings.inMemory(),
                               runner: runner, apps: FakeApps(), news: news,
                               interfaces: interfaces, exit: exit, speed: speed,
                               work: .inline)
        engine.refresh()
        return (engine, news)
    }

    /// **The control.** The same command on the tunnel that carries the route
    /// reaches the page. The fake blocks until released, as `networkQuality`
    /// holds its thread, or the run would be past the state asserted on.
    func testAMeasurementTheEngineAcceptsIsAnnouncedAsItStarts() async {
        let speed = FakeSpeed()
        speed.blocksUntilReleased = true
        let running = XCTestExpectation(description: "the run has started")
        speed.onStart = { running.fulfill() }
        let (engine, news) = twoTunnels(speed)
        defer { speed.release(); engine.deactivate() }

        let seen = await stateEvents(on: news) { engine.measureSpeed("routed") }
        await fulfillment(of: [running], timeout: 5)

        XCTAssertTrue(seen.contains { $0.tunnels.contains { $0.measuring } }, """
            the accepted measurement never reached the news, so this file's \
            fixture cannot say anything about the refusal below
            """)
    }

    /// The refusal reaches the page although it changes no field. Counted rather
    /// than matched on content, since the refusal emits the same fields; the
    /// replayed event is the first of the count.
    func testAMeasurementRefusedOverAQuietTunnelStillReachesThePage() async {
        let speed = FakeSpeed()
        let (engine, news) = twoTunnels(speed)
        defer { engine.deactivate() }

        let quiet = await stateEvents(on: news)
        XCTAssertEqual(quiet.count, 1,
                       "precondition: the state is not settled, so a count means nothing")
        XCTAssertEqual(quiet.last?.tunnels.count, 2,
                       "precondition: both tunnels never reached the page")
        XCTAssertEqual(quiet.last?.tunnels.first(where: { $0.name == "beside" })?.exit,
                       .besideTunnel,
                       "precondition: «beside» carries the route, so nothing is refused")

        let seen = await stateEvents(on: news) { engine.measureSpeed("beside") }

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
