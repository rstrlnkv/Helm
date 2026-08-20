// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **`VPNDropSettle` deferred the announcement and not the forgetting.**
///
/// `refreshNow` does two things with a tunnel that is missing from `--nc list`:
/// it strikes the configuration out of `_cameUp` and its name out of
/// `_autoConnected` — «what Helm raised and is holding» — and it records the
/// fall in `fellAt` so the verdict can be taken later. The settle window was
/// added to the second half only. The first half still runs on the **first**
/// read that sees the tunnel down, which is exactly the read the window exists
/// to distrust: `ADropThatHealedIsNotAnnouncedTests` documents a
/// NetworkExtension tunnel re-handshaking on a Wi-Fi change and coming back in
/// three seconds, measured twice in two days of the owner's log.
///
/// So the blip is not announced — and it costs Helm the tunnel anyway. After it
/// heals, `_cameUp` and `_autoConnected` are empty while the tunnel is up and
/// Helm raised it, and nothing ever puts them back: the loop that re-adopts a
/// connected tunnel is gated on `_autoConnected.contains(name)`, which the same
/// read has just cleared. Everything downstream reads off those two books, so
/// what the blip actually takes away is the **next** drop — the one this
/// module's only interrupting notice exists for, and the one the person needs
/// because they are now sending in clear having last been told they were not.
///
/// The three-second blip is the cheap case. Any tunnel that re-handshakes once
/// spends the rest of the session unwatched.
final class ABlipDoesNotCostHelmItsTunnelTests: XCTestCase {

    private let bundleID = "com.example.app"
    private let identity = CodeIdentity(signingID: "com.example.app", teamID: "ABCDE12345")
    private let header = "Available network connection services:"

    private func row(_ status: String) -> String {
        "* (\(status)) 11111111-1111-1111-1111-111111111111 VPN (com.x.work) \"work\" [VPN:com.x.work]"
    }

    private func list(_ status: String) -> String {
        [header, row(status)].joined(separator: "\n")
    }

    /// A tunnel Helm itself raised, because that is what a drop is about:
    /// `_autoConnected` is written by an automatic connect — a rule firing for an
    /// app that launched — and not by a command somebody sent.
    ///
    /// The fixture is spelled here rather than shared with
    /// `ADropThatHealedIsNotAnnouncedTests`: its builder is `private`, and a
    /// helper that reaches across two files in this target would have to move to
    /// `HelmTestSupport`, which cannot import a module engine.
    private func engineHoldingTheTunnel(_ runner: FakeRunner, _ clock: TestClock) -> VPNEngine {
        let apps = FakeApps()
        apps.identities[bundleID] = identity
        apps.bundleIDs = [bundleID]
        let settings = VPNSettings(store: NamespacedStore(namespace: "vpn",
                                                          backing: InMemoryKeyValueStore()))
        settings.setRulesJSON(VPNRules.encode(
            [bundleID: VPNAppRule(vpnName: "work", identity: identity)]))
        runner.listOutput = list("Disconnected")
        // Every port named, none defaulted: three of the defaults reach the
        // network or run a tool for fifteen seconds
        // (`NoTestTakesAProductionPortTests`).
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(),
                               speed: FakeSpeed(), now: { clock.now }, work: .inline)
        engine.activate()
        runner.listOutput = list("Connected")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("work"),
                      "precondition: Helm is not holding the tunnel, so nothing here is a drop")
        engine.clearLastAutomationForTesting()
        return engine
    }

    /// Down for three seconds, up again — the measured blip — and Helm still
    /// holds the tunnel afterwards.
    ///
    /// This is the mechanism, asserted where it lives. The test below is the
    /// harm.
    func testAHealedBlipLeavesHelmStillHoldingTheTunnel() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = engineHoldingTheTunnel(runner, clock)

        runner.listOutput = list("Disconnected")
        engine.refresh()
        clock.advance(3)
        runner.listOutput = list("Connected")
        engine.refresh()

        XCTAssertNil(engine.lastAutomation,
                     "precondition: the blip was announced, which is a different defect")
        XCTAssertTrue(engine.autoConnected.contains("work"), """
            a three-second re-handshake struck the tunnel out of the book of what \
            Helm raised, while the tunnel is up and Helm did raise it — so the \
            page's «automatic» count is wrong and the quit rule owns nothing
            """)
    }

    /// **The harm.** A blip that healed leaves the tunnel unwatched, so the loss
    /// that follows is never reported at all.
    ///
    /// The second fall is a real one — down, and still down a whole window
    /// later. Announced from a clean session (`ADropThatHealedIsNotAnnounced\
    /// Tests.testATunnelThatStaysDownIsAnnouncedOnceTheWindowHasPassed`), and
    /// silent here, with nothing between the two but a re-handshake the module
    /// went out of its way not to announce.
    func testTheRealDropAfterAHealedBlipIsStillAnnounced() throws {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = engineHoldingTheTunnel(runner, clock)

        // The blip: down, and back three seconds later.
        runner.listOutput = list("Disconnected")
        engine.refresh()
        clock.advance(3)
        runner.listOutput = list("Connected")
        engine.refresh()
        XCTAssertNil(engine.lastAutomation, "precondition: the blip itself was announced")

        // A minute of ordinary life, then the tunnel really goes.
        clock.advance(60)
        runner.listOutput = list("Disconnected")
        engine.refresh()
        clock.advance(VPNDropSettle.window)
        engine.refresh()

        let firing = try XCTUnwrap(engine.lastAutomation, """
            the tunnel was lost for good and nothing was said, because a \
            three-second blip earlier in the session had already emptied the \
            books the drop is read out of — the one notice this module \
            interrupts for, gone for the rest of the session after one \
            re-handshake
            """)
        XCTAssertEqual(firing.kind, .dropped)
        XCTAssertEqual(firing.name, "work")
    }

    /// **The boundary the brief names: a drop that heals exactly at the
    /// deadline.**
    ///
    /// `VPNDropSettle.verdict` answers `.healed` for a tunnel that is up at any
    /// age, and the engine schedules its one wake-up for exactly
    /// `VPNDropSettle.window` after the fall — so the read that decides is the
    /// one taken at the deadline itself, with the tunnel back. Up must win the
    /// tie, or the notice fires on the very blip it was written to swallow.
    func testATunnelBackAtTheDeadlineIsHealedRatherThanAnnounced() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = engineHoldingTheTunnel(runner, clock)

        runner.listOutput = list("Disconnected")
        engine.refresh()
        clock.advance(VPNDropSettle.window)
        runner.listOutput = list("Connected")
        engine.refresh()

        XCTAssertNil(engine.lastAutomation, """
            a tunnel that was back at the instant the window closed was \
            announced as lost — the tie goes to the tunnel being up
            """)
    }
}
