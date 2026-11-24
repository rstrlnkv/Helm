// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_VPN_Engine

/// **The notifications that arrive before a re-read runs are one re-read.
/// `SCDynamicStore` does not deliver one event.**
///
/// One tunnel coming up moves the global IPv4 entity, each service's IPv4 entity
/// and the Setup entity, and `DynamicStoreNetworkWatch` subscribes to all three,
/// so the store fires in bursts of five to eleven within a second. Each re-read
/// costs a `scutil --nc list` subprocess, plus a `--nc status` for any connected
/// tunnel whose reading is not cached, on the queue every connect has to get
/// through. The port carries no detail, so how often to re-read is the engine's
/// job: the engine, not the port, must coalesce.
///
/// The fake fires from one thread, in a burst, the way the store's serial queue
/// does. The count is taken on `.background`, the queue the app runs on, because
/// `VPNWorkQueue.inline` runs a delayed block at once, and it is held until it
/// stops moving before it is read.
final class ANetworkBlipIsNotSevenSubprocessesTests: XCTestCase {

    /// Twenty rather than the store's usual seven, so that «fewer than one
    /// subprocess each» is not a reading a lucky schedule can produce.
    private static let burst = 20

    /// At most this many `--nc list` runs may follow the whole burst.
    ///
    /// One already in flight when the burst began, one for the leading edge,
    /// one for the trailing edge, and one spare: a ceiling with room in it, not a
    /// threshold tuned to pass.
    private static let affordable = 4

    private let list = """
        Available network connection services:
        * (Connected) AAAAAAAA-0000-0000-0000-000000000001 VPN (com.x.work) "work" [VPN:com.x.work]
        """

    private let status = scutilStatus(primary: true, extra: ["Status : 2"])

    /// Waits until `tally` has not moved for `still`, and fails at `deadline`.
    ///
    /// A reading taken too early would be *low*, the direction that passes
    /// with the defect present, so no fixed sleep.
    private func settled(_ tally: LockedCount, still: TimeInterval = 0.4,
                         deadline: TimeInterval = 8,
                         file: StaticString = #filePath, line: UInt = #line) -> Int {
        let started = Date()
        var last = tally.value
        var unchangedSince = Date()
        while Date().timeIntervalSince(started) < deadline {
            Thread.sleep(forTimeInterval: 0.025)
            let now = tally.value
            if now != last {
                last = now
                unchangedSince = Date()
            } else if Date().timeIntervalSince(unchangedSince) >= still {
                return now
            }
        }
        XCTFail("the count of `--nc list` runs never held still for \(still) s within \(deadline) s", file: file, line: line)
        return tally.value
    }

    func testABurstFromTheStoreIsNotOneScutilRunEach() {
        let runner = FakeRunner(list: list)
        runner.statusOutput["work"] = status
        let listReads = LockedCount()
        // Counted through the fake's own locked hook, on the thread that issued
        // the command: `issued` is a plain array the module's queue appends to,
        // and reading it from here would be both a race and a poll.
        runner.onRun = { args in if args == ["--nc", "list"] { listReads.bump() } }

        let network = FakeNetwork()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        interfaces.counters = ["utun4": (in: 1_000, out: 2_000)]
        let engine = VPNEngine(settings: VPNSettings.inMemory(),
                               runner: runner, apps: FakeApps(), network: network,
                               interfaces: interfaces, exit: FakeExit(), speed: FakeSpeed(),
                               work: .background)
        defer { engine.deactivate() }

        engine.activate()
        let beforeTheBurst = settled(listReads)
        XCTAssertGreaterThanOrEqual(beforeTheBurst, 1, """
            precondition: the engine never read the list at all, so a count of \
            what a burst costs is a count of nothing
            """)
        XCTAssertEqual(network.starts, 1, "precondition: nothing is watching the network")

        for _ in 0..<Self.burst { network.fire() }
        let afterTheBurst = settled(listReads)

        XCTAssertGreaterThan(afterTheBurst, beforeTheBurst, """
            precondition: the burst reached the engine at all — a re-read count \
            that did not move means this test measured a disconnected fake
            """)
        XCTAssertLessThanOrEqual(afterTheBurst - beforeTheBurst, Self.affordable, """
            \(Self.burst) network notifications delivered in one burst cost \
            \(afterTheBurst - beforeTheBurst) runs of `scutil --nc list`, one \
            subprocess each at 16 ms, on the queue every connect and disconnect \
            has to get through. The store really does fire this way — seven \
            times in a second on the owner's machine — and nothing between the \
            callback and `refreshNow` coalesces
            """)
    }
}
