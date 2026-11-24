// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import XCTest
@testable import Module_VPN_Engine

/// **A blip that heals costs Helm neither the announcement nor the tunnel.**
///
/// `refreshNow` does two things with a tunnel missing from `--nc list`: it
/// strikes it out of `_cameUp` and `_autoConnected` («what Helm raised and is
/// holding») and records the fall in `fellAt` for the verdict. Both halves wait
/// for `VPNDropSettle`: a NetworkExtension tunnel re-handshakes on a Wi-Fi change
/// and is back in seconds (`ADropThatHealedIsNotAnnouncedTests`). Struck on the
/// first read, the books stay empty after it heals, because the loop that
/// re-adopts a connected tunnel is gated on `_autoConnected.contains(name)`, and
/// the next real drop, the one this module interrupts for, is never announced.
final class ABlipDoesNotCostHelmItsTunnelTests: XCTestCase {

    /// Down for three seconds, up again, and Helm still holds the tunnel
    /// afterwards. This is the mechanism; the test below is the harm.
    func testAHealedBlipLeavesHelmStillHoldingTheTunnel() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = blipEngineHoldingTheTunnel(runner, clock)

        runner.listOutput = blipList("Disconnected")
        engine.refresh()
        clock.advance(3)
        runner.listOutput = blipList("Connected")
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
    /// The second fall is a real one: down, and still down a whole window later.
    func testTheRealDropAfterAHealedBlipIsStillAnnounced() throws {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = blipEngineHoldingTheTunnel(runner, clock)

        // The blip: down, and back three seconds later.
        runner.listOutput = blipList("Disconnected")
        engine.refresh()
        clock.advance(3)
        runner.listOutput = blipList("Connected")
        engine.refresh()
        XCTAssertNil(engine.lastAutomation, "precondition: the blip itself was announced")

        // A minute of ordinary life, then the tunnel really goes.
        clock.advance(60)
        runner.listOutput = blipList("Disconnected")
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

    /// **A drop that heals exactly at the deadline is healed.**
    ///
    /// The engine's one wake-up comes exactly `VPNDropSettle.window` after the
    /// fall, so the read that decides is taken at the deadline itself. Up must
    /// win the tie, or the notice fires on the very blip it was written to
    /// swallow.
    func testATunnelBackAtTheDeadlineIsHealedRatherThanAnnounced() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = blipEngineHoldingTheTunnel(runner, clock)

        runner.listOutput = blipList("Disconnected")
        engine.refresh()
        clock.advance(VPNDropSettle.window)
        runner.listOutput = blipList("Connected")
        engine.refresh()

        XCTAssertNil(engine.lastAutomation, """
            a tunnel that was back at the instant the window closed was \
            announced as lost — the tie goes to the tunnel being up
            """)
    }
}
