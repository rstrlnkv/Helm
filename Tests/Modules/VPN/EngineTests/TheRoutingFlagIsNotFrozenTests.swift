// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **`interfaceOf` caches four facts and only one of them holds still.**
///
/// `VPNEngine.readInterfaces` asks `scutil --nc status` once per tunnel and
/// keeps the whole `VPNStatusParser.Reading` until that tunnel goes. Its comment
/// justifies the cache with one of the four fields: «a tunnel's `utunN` does not
/// change while it is up». True — and the same value carries
/// `isPrimaryInterface`, which is **whether this Mac's traffic is leaving
/// through the tunnel**, and that changes without the tunnel moving at all:
/// Wi-Fi to Ethernet, a second tunnel taking the route, a captive network
/// coming and going. `VPNExitAsk.routeMoved` exists because the module knows
/// this; the reading it is compared against is frozen.
///
/// It is a local memory of a live external fact with no reverse channel from
/// the port that knows — CLAUDE.md § «Anything that can stop being true on its
/// own owns a channel to say so», and the same shape as
/// `LayoutEngine.tapped`: set once against something macOS can revoke.
///
/// **The branch it decides is reached whenever the dynamic store answers nil.**
/// `VPNInterfacePort.primaryInterface()` documents nil as two states at once, «a
/// Mac with no default route» and «the store could not be read», and
/// `VPNExitVerdict.of` falls back to the connection's own flag for exactly that
/// case — «which answers when the dynamic store could not be opened at all». So
/// the fallback that exists for the unreadable store is the one reading that can
/// never be taken again.
///
/// Both directions are wrong and the second is the dangerous one: an absent
/// answer reads as «not known», a stale one reads as an answer.
final class TheRoutingFlagIsNotFrozenTests: XCTestCase {

    private let list = """
        Available network connection services:
        * (Connected) AAAAAAAA-0000-0000-0000-000000000001 VPN (com.x.work) "work" [VPN:com.x.work]
        """

    /// `scutil --nc status "work"` as the tool writes it. The flag is the only
    /// thing that moves between the two readings.
    private func status(primary: Bool) -> String {
        """
        Connected
        Extended Status <dictionary> {
          IPv4 : <dictionary> {
            InterfaceName : utun4
          }
          IsPrimaryInterface : \(primary ? 1 : 0)
          LastStatusChangeTime : 08/19/2026 14:57:22
          Status : 2
        }
        """
    }

    /// **The store answers nil**, which is the state the connection's own flag
    /// is consulted for. Every port named.
    private func engine(_ runner: FakeRunner)
        -> (engine: VPNEngine, transport: LocalTransport) {
        let interfaces = FakeInterfaces()
        interfaces.primary = nil
        interfaces.counters = ["utun4": (in: 1_000, out: 2_000)]
        // Held open, the way the real port is for up to eight seconds — and so
        // the exit check's own `emitState` does not race this test's reading
        // (`TheTestQueueIsAsSerialAsTheRealOneTests`).
        let exit = FakeExit()
        exit.hangs = true
        let transport = LocalTransport()
        let engine = VPNEngine(settings: VPNSettings(store: NamespacedStore(
                                    namespace: "vpn", backing: InMemoryKeyValueStore())),
                               runner: runner, apps: FakeApps(), transport: transport,
                               interfaces: interfaces, exit: exit, speed: FakeSpeed(),
                               work: .inline)
        return (engine, transport)
    }

    private func verdict(on transport: LocalTransport) async -> VPNExitVerdict? {
        await lastState(on: transport)?.tunnels.first?.exit
    }

    /// The control. A tunnel whose first reading says it holds the route is read
    /// correctly — so the two tests below are about the *second* reading and not
    /// about a fixture that never gets the flag right.
    func testTheFlagIsReadWhenItIsFirstAsked() async {
        let runner = FakeRunner()
        runner.listOutput = list
        runner.statusOutput["work"] = status(primary: true)
        let (engine, transport) = self.engine(runner)
        defer { engine.deactivate() }

        engine.refresh()
        let seen = await verdict(on: transport)
        XCTAssertEqual(seen, .throughTunnel(countryCode: nil),
                       "precondition: the tool's own routing flag is not read at all")
    }

    /// **The route arrives at the tunnel and the page never says so.**
    ///
    /// A tunnel comes up before the route moves onto it, which is the ordinary
    /// order of events — the handshake finishes, then the routing table is
    /// rewritten. The first status read catches the moment in between.
    func testARouteThatMovesOntoTheTunnelIsNoticed() async {
        let runner = FakeRunner()
        runner.listOutput = list
        runner.statusOutput["work"] = status(primary: false)
        let (engine, transport) = self.engine(runner)
        defer { engine.deactivate() }

        engine.refresh()
        let seen = await verdict(on: transport)
        XCTAssertEqual(seen, .besideTunnel,
                       "precondition: the first reading was not the one this test starts from")

        // The routing table is rewritten. The tunnel has not moved.
        runner.statusOutput["work"] = status(primary: true)
        engine.refresh()
        engine.refresh()

        let seenAgain = await verdict(on: transport)
        XCTAssertEqual(seenAgain, .throughTunnel(countryCode: nil), """
            the tunnel took the default route and the page went on saying the \
            traffic goes around it, because the reading was cached at the one \
            moment the flag was false and is never taken again while the tunnel \
            is up
            """)
    }

    /// **The worse direction: the route leaves and the tick stays green.**
    ///
    /// A second tunnel takes the default route, or the Mac moves onto Ethernet.
    /// The first tunnel is still up and still on `utun4`, and every fact about
    /// where the traffic actually goes has changed. An absent answer reads as
    /// «not known»; this one reads as «checked, and you are covered».
    func testARouteThatLeavesTheTunnelIsNoticed() async {
        let runner = FakeRunner()
        runner.listOutput = list
        runner.statusOutput["work"] = status(primary: true)
        let (engine, transport) = self.engine(runner)
        defer { engine.deactivate() }

        engine.refresh()
        let seen = await verdict(on: transport)
        XCTAssertEqual(seen, .throughTunnel(countryCode: nil),
                       "precondition: the first reading was not the one this test starts from")

        runner.statusOutput["work"] = status(primary: false)
        engine.refresh()
        engine.refresh()

        let seenAgain = await verdict(on: transport)
        XCTAssertEqual(seenAgain, .besideTunnel, """
            the default route left the tunnel and the page kept the green tick: \
            the routing flag was cached with the interface at the first status \
            read and the tool is never asked again while the tunnel is up, so \
            the one sentence this feature exists to get right is a reassurance \
            nobody checked
            """)
    }
}
