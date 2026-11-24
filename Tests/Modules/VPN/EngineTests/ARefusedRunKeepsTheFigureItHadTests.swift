// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// **A measurement that refused must not take the last one with it.**
///
/// Only the tunnel going drops a reading (`VPNEngine.lastSpeed`,
/// `forgetWhatIsGone`). `HelmMeasuringSlot` demotes the old figure to quiet ink
/// for the run because it is still the only reading the person has, and
/// `VPNTunnelStrip` reads «Measure again» while a figure is there. A run the
/// tool could not characterise (a `-1009`, a tool killed at its deadline, a
/// half-written JSON `VPNSpeedReading.parse` refuses) has no news of its own,
/// so it must not erase the figure: assigning nil through a `Dictionary`
/// subscript would remove the key.
final class ARefusedRunKeepsTheFigureItHadTests: XCTestCase {

    private let header = "Available network connection services:"
    private let identifier = "AAAAAAAA-0000-0000-0000-000000000001"

    private func list() -> String {
        [header,
         "* (Connected) \(identifier) VPN (com.x.routed) \"routed\" [VPN:com.x.routed]"]
            .joined(separator: "\n")
    }

    /// One tunnel, up, carrying the default route, so the engine accepts a
    /// measurement on it. Every port named (`NoTestTakesAProductionPortTests`).
    /// **A quiet link**: moving counters would make every payload differ, and a
    /// figure could survive on screen by luck.
    private func oneTunnel(_ speed: FakeSpeed)
        -> (engine: VPNEngine, news: EngineNews<VPNEngine.StatePayload>) {
        let runner = FakeRunner(list: list())
        runner.statusOutput["routed"] = scutilStatus(primary: true, extra: ["Status : 2"])
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        interfaces.counters = ["utun4": (in: 1_000_000, out: 1_000_000)]
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

    /// Waits for a state the matcher accepts, subscribing **before** the act so
    /// nothing can go by unseen.
    private func waitForState(_ news: EngineNews<VPNEngine.StatePayload>, _ what: String,
                              until matches: @escaping @Sendable (VPNEngine.StatePayload) -> Bool,
                              during act: () async -> Void) async {
        let arrived = LockedCount()
        let events = news.stream()
        let watcher = Task {
            for await payload in events where !isSentinel(payload) && matches(payload) {
                arrived.bump()
                return
            }
        }
        await act()
        await waitUntilReached(what, within: .seconds(10)) { arrived.value > 0 }
        watcher.cancel()
    }

    func testARunTheToolRefusesLeavesTheLastFigureOnThePage() async {
        let taken = Date(timeIntervalSince1970: 1_700_000_000)
        let speed = FakeSpeed()
        speed.answer = VPNSpeedReading(down: 343, up: 358, at: taken, took: 19)
        let (engine, news) = oneTunnel(speed)
        defer { speed.release(); engine.deactivate() }

        // An assertion that a figure survived is green when no figure ever
        // arrived, so the first reading must reach the page.
        await waitForState(news, "the first reading reached the page",
                           until: { $0.tunnels.first?.speed != nil },
                           during: { engine.measureSpeed("routed") })
        let first = await lastState(on: news)
        XCTAssertEqual(first?.tunnels.first?.speed?.down, 343,
                       "precondition: no figure ever reached the page, so nothing below "
                       + "is about a figure being kept")
        XCTAssertEqual(first?.tunnels.first?.measuring, false,
                       "precondition: the first run has not ended, so the second cannot start")

        // A second run that the tool refuses. **It holds its thread**, as the
        // real tool does, or the two ends of the run would be one event
        // (Architecture/TestsAndMeasurement.md § Fakes).
        speed.answer = nil
        speed.blocksUntilReleased = true
        await waitForState(news, "the second run is in flight",
                           until: { $0.tunnels.first?.measuring == true },
                           during: { engine.measureSpeed("routed") })
        XCTAssertEqual(speed.askedFor.count, 2,
                       "precondition: the second run was refused by the engine rather than "
                       + "reaching the port, so this says nothing about a refusal")

        await waitForState(news, "the second run ended",
                           until: { $0.tunnels.first?.measuring == false },
                           during: { speed.release() })

        let after = await lastState(on: news)
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
