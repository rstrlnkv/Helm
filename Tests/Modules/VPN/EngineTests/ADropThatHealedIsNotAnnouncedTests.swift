// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_VPN_Engine

/// **The drop notice fired on a tunnel that was back three seconds later.**
///
/// It is this module's only interrupting signal, and its own comment says why —
/// «the person is now sending everything in clear having last been told they
/// were behind a tunnel». It was fired on the first `scutil --nc list` read that
/// showed a watched tunnel not up, and a NetworkExtension tunnel re-handshaking
/// on a Wi-Fi change or a wake does exactly that.
///
/// Measured on the owner's machine, in the log and in the tool in the same
/// breath: `automatic connection dropped` at 14:57:19 against
/// `LastStatusChangeTime : 14:57:22`. Twice in the two days of log there was to
/// read. A signal that cries wolf on a blip is a signal people switch off, and
/// then the real drop is silent too.
///
/// Past defect: commit 038fee7f, «fix(vpn): a drop that healed in three seconds is not announced».
final class ADropThatHealedIsNotAnnouncedTests: XCTestCase {

    /// The measured case: down at one read, up at the next, three seconds later.
    func testATunnelThatComesBackInsideTheWindowIsNeverAnnounced() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = blipEngineHoldingTheTunnel(runner, clock)

        runner.listOutput = blipList("Disconnected")
        engine.refresh()
        XCTAssertNil(engine.lastAutomation, """
            the drop was announced on the first read that saw the tunnel down, \
            which is what a re-handshake looks like
            """)

        clock.advance(3)
        runner.listOutput = blipList("Connected")
        engine.refresh()
        XCTAssertNil(engine.lastAutomation,
                     "a tunnel that came back was announced as lost")

        // And it stays unannounced however long anybody waits afterwards.
        clock.advance(VPNDropSettle.window * 4)
        engine.refresh()
        XCTAssertNil(engine.lastAutomation, """
            the fall was remembered past the tunnel's own return and announced \
            later, which is the same false alarm with a delay on it
            """)
    }

    /// **And a real loss is still reported** — the half that makes the test
    /// above mean anything. A settle window that swallowed every drop would
    /// satisfy the first test and leave the module with no signal at all.
    func testATunnelThatStaysDownIsAnnouncedOnceTheWindowHasPassed() throws {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = blipEngineHoldingTheTunnel(runner, clock)

        runner.listOutput = blipList("Disconnected")
        engine.refresh()
        XCTAssertNil(engine.lastAutomation, "precondition: it was announced before the window")

        clock.advance(VPNDropSettle.window)
        engine.refresh()
        let firing = try XCTUnwrap(engine.lastAutomation, """
            a tunnel that has been down for the whole window was never reported, \
            so the one notice this module interrupts for is gone
            """)
        XCTAssertEqual(firing.kind, .dropped)
        XCTAssertEqual(firing.name, "work")
    }

    /// Announced once, not at every refresh afterwards.
    func testTheLossIsAnnouncedOnceRatherThanAtEveryRefresh() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = blipEngineHoldingTheTunnel(runner, clock)

        runner.listOutput = blipList("Disconnected")
        engine.refresh()
        clock.advance(VPNDropSettle.window)
        engine.refresh()
        XCTAssertNotNil(engine.lastAutomation, "precondition: it was never announced")

        engine.clearLastAutomationForTesting()
        clock.advance(VPNDropSettle.window)
        engine.refresh()
        XCTAssertNil(engine.lastAutomation, """
            the same loss was announced again on a later refresh, so a tunnel \
            left down keeps interrupting for as long as it is down
            """)
    }

    // MARK: - The rule itself

    func testUpAtAnyAgeIsHealedRatherThanAnnounced() {
        let fell = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(VPNDropSettle.verdict(fellAt: fell, isUpNow: true,
                                             now: fell.addingTimeInterval(1)), .healed)
        XCTAssertEqual(VPNDropSettle.verdict(fellAt: fell, isUpNow: true,
                                             now: fell.addingTimeInterval(3600)), .healed, """
            a tunnel that took an hour to come back was announced as lost — up is \
            not a loss whatever the clock says
            """)
    }

    func testTheWindowIsWhatSeparatesWaitingFromAnnouncing() {
        let fell = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(VPNDropSettle.verdict(fellAt: fell, isUpNow: false, now: fell), .waiting)
        XCTAssertEqual(VPNDropSettle.verdict(
            fellAt: fell, isUpNow: false,
            now: fell.addingTimeInterval(VPNDropSettle.window - 0.1)), .waiting)
        XCTAssertEqual(VPNDropSettle.verdict(
            fellAt: fell, isUpNow: false,
            now: fell.addingTimeInterval(VPNDropSettle.window)), .announce)
    }

    /// A clock that went backwards waits rather than announcing: a negative
    /// interval is not the window having passed, and late news beats invented
    /// news.
    func testAClockThatWentBackwardsDoesNotAnnounce() {
        let fell = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(VPNDropSettle.verdict(fellAt: fell, isUpNow: false,
                                             now: fell.addingTimeInterval(-3600)), .waiting)
    }
}
