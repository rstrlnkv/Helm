// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **One network event is one re-read. `SCDynamicStore` does not deliver one
/// event.**
///
/// Measured in the owner's own `~/Library/Logs/Helm/helm.log`, not reasoned
/// about: `network state changed; re-reading` arrives in bursts of up to seven
/// inside a single second — counts per second across the log of 7, 7, 7, 6, 5,
/// 5, 5, 5 — and one connect is followed by five to eleven of them in under half
/// a second:
///
/// ```
/// 23:20:20.284 [info] [vpn] connect vpn#7b99
/// 23:20:20.526 [info] [vpn] network state changed; re-reading
/// 23:20:20.540 [info] [vpn] network state changed; re-reading
/// 23:20:20.611 [info] [vpn] network state changed; re-reading
/// 23:20:20.661 [info] [vpn] network state changed; re-reading
/// 23:20:20.678 [info] [vpn] network state changed; re-reading
/// 23:20:21.162 [info] [vpn] settled: …
/// ```
///
/// That is what the store does when one tunnel comes up: the global IPv4 entity
/// moves, each service's IPv4 entity moves, the Setup entity moves, and
/// `DynamicStoreNetworkWatch` subscribes to all three with no coalescing
/// anywhere between the callback and `refreshNow`. Every one of them costs a
/// `scutil --nc list` — a subprocess this repository measures at 16 ms — plus a
/// `--nc status` for any connected tunnel whose reading is not cached yet.
///
/// `ScanCoordinator` has an explicit on-change-only rule for exactly this shape.
/// Nothing in this module has earned an exception from it: the port's own
/// documentation says «the port carries no detail: what changed is `scutil`'s
/// answer to give, and the engine re-reads the list either way» — which makes
/// deciding *how often* to re-read the engine's job and nobody else's.
///
/// **The fake is exactly as free as the real port has been measured to be.** It
/// fires from one thread, in a burst, the way the store's own serial queue does.
/// A coalescer put in `DynamicStoreNetworkWatch` alone would leave this test red
/// on purpose: the engine is what turns a notification into a subprocess, and it
/// is the thing that has to be robust to a port that fires seven times.
///
/// The count is taken on `.background`, the queue the app runs on, because
/// coalescing is about time and `VPNWorkQueue.inline` runs a delayed block at
/// once. It is held until it stops moving before it is read.
final class ANetworkBlipIsNotSevenSubprocessesTests: XCTestCase {

    /// A counter a `@Sendable` hook can add to.
    ///
    /// `ProgressBox` in `HelmTestSupport` is the same lock and the same `Int`
    /// and it *records* rather than *adds*, so it cannot count calls. This
    /// belongs beside it; it is here only because `Tests/Support` has another
    /// writer in it today.
    private final class Tally: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func add() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// What the store delivered when one tunnel came up, on the machine the log
    /// above came from. Twenty rather than seven so that «fewer than one
    /// subprocess each» is not a reading a lucky schedule can produce.
    private static let burst = 20

    /// At most this many `--nc list` runs may follow the whole burst.
    ///
    /// Four, and each of the four is a read somebody can name: one already in
    /// flight when the burst began, one for the leading edge, one for the
    /// trailing edge, and one spare. A burst arriving inside a millisecond
    /// collapses to one or two under any coalescing window at all, so this is a
    /// ceiling with room in it rather than a threshold tuned to pass.
    private static let affordable = 4

    private let list = """
        Available network connection services:
        * (Connected) AAAAAAAA-0000-0000-0000-000000000001 VPN (com.x.work) "work" [VPN:com.x.work]
        """

    private let status = """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun4
          }
          IsPrimaryInterface : 1
          Status : 2
        }
        """

    /// Waits until `tally` has not moved for `still`, or gives up at `deadline`.
    ///
    /// A single reading taken too early would be *low*, which is the direction
    /// that makes this test pass while the defect is there — so the count is
    /// held until it stops moving rather than read after a fixed sleep.
    private func settled(_ tally: Tally, still: TimeInterval = 0.4,
                         deadline: TimeInterval = 8) -> Int {
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
        return tally.value
    }

    func testABurstFromTheStoreIsNotOneScutilRunEach() {
        let runner = FakeRunner()
        runner.listOutput = list
        runner.statusOutput["work"] = status
        let listReads = Tally()
        // Counted through the fake's own locked hook, on the thread that issued
        // the command: `issued` is a plain array the module's queue appends to,
        // and reading it from here would be both a race and a poll.
        runner.onRun = { args in if args == ["--nc", "list"] { listReads.add() } }

        let network = FakeNetwork()
        let interfaces = FakeInterfaces()
        interfaces.primary = "utun4"
        interfaces.counters = ["utun4": (in: 1_000, out: 2_000)]
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
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
