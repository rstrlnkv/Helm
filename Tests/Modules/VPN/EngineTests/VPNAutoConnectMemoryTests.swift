// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// `_cameUp` lets `refreshNow` tell "not up yet" from "came up and then
/// went".
///
/// `disconnectNow` empties `_cameUp` as well as `_autoConnected`. Left out of
/// step, the next time Helm raises the same VPN the first refresh after the
/// connect — which usually still reports the old status — would read the name
/// as a tunnel that went and forget that Helm raised it.
///
/// Asserted on the engine's own record rather than on a rendered number: what
/// `autoConnected` is *for* is answering "did Helm raise this", and the page's
/// AUTOMATIC count is one reader of it.
final class VPNAutoConnectMemoryTests: XCTestCase {

    /// The second session with the same app. Launch → connect → up → quit →
    /// disconnect → launch again. At the end Helm has just issued `--nc start`
    /// itself, so it must still know the connection is its own.
    func test_a_vpn_raised_a_second_time_is_still_its_own() {
        let runner = FakeRunner()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner,
                               apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        // First session: Helm raises it, and a later refresh sees it up.
        runner.listOutput = scutilListRow("Disconnected")
        engine.connect("A", auto: true)
        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "a connect Helm has just issued is Helm's, whatever scutil still says")
        runner.listOutput = scutilListRow("Connected")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("A"))

        // The app quits: Helm takes its own connection down.
        runner.listOutput = scutilListRow("Disconnected")
        engine.disconnect("A", auto: false)
        XCTAssertFalse(engine.autoConnected.contains("A"),
                       "a connection Helm dropped is no longer Helm's")

        // The app launches again. `scutil --nc start` is asynchronous, so the
        // refresh that follows still reports Disconnected — the case `_cameUp`
        // exists for.
        engine.connect("A", auto: true)

        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "Helm forgot a VPN it had just raised, because the memory of the "
                      + "previous session's `came up` was never cleared when it "
                      + "disconnected: autoConnected = \(engine.autoConnected)")
    }

    /// The other half, so a fix cannot buy the test above by never forgetting
    /// anything: a connection Helm raised, that came up and then dropped on its
    /// own, stops being Helm's.
    ///
    /// **The deadline is `VPNDropSettle.window`, not the first read that saw it
    /// down**: a re-handshake of a few seconds must not empty this book while the
    /// tunnel is up and Helm is holding it (`ABlipDoesNotCostHelmItsTunnelTests`).
    /// Both ends are asserted: still Helm's inside the window, not Helm's past it.
    func test_a_vpn_that_came_up_and_then_went_is_forgotten() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner,
                               apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               now: { clock.now }, work: .inline)

        runner.listOutput = scutilListRow("Disconnected")
        engine.connect("A", auto: true)
        runner.listOutput = scutilListRow("Connected")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("A"))

        // The network went, or somebody stopped it in System Settings.
        runner.listOutput = scutilListRow("Disconnected")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "a fall inside the settle window was taken for a loss, which is the "
                      + "read `VPNDropSettle` exists to distrust")

        clock.advance(VPNDropSettle.window)
        engine.refresh()

        XCTAssertFalse(engine.autoConnected.contains("A"),
                       "a connection that came up and then went is not up any more")
    }

    /// And the case that mechanism protects: a connect whose status has not
    /// caught up yet must survive any number of refreshes before it does.
    func test_a_vpn_that_has_not_come_up_yet_is_not_forgotten() {
        let runner = FakeRunner()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner,
                               apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        runner.listOutput = scutilListRow("Disconnected")
        engine.connect("A", auto: true)
        engine.refresh()
        engine.refresh()

        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "a connection Helm asked for and that has not answered yet is still Helm's")
    }

    /// What the disconnect's clearing of `_cameUp` is for, seen past the settle
    /// window: the session before left its `came up` behind, the VPN is raised
    /// again and has not answered yet, and the old entry must not be read as a
    /// tunnel that went.
    func test_a_second_session_is_not_forgotten_for_the_first_ones_fall() {
        let runner = FakeRunner()
        let clock = TestClock()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner,
                               apps: FakeApps(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               now: { clock.now }, work: .inline)

        runner.listOutput = scutilListRow("Disconnected")
        engine.connect("A", auto: true)
        runner.listOutput = scutilListRow("Connected")
        engine.refresh()
        runner.listOutput = scutilListRow("Disconnected")
        engine.disconnect("A", auto: false)
        engine.connect("A", auto: true)

        engine.refresh()
        clock.advance(VPNDropSettle.window)
        engine.refresh()

        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "the previous session's `came up` outlived its disconnect and was "
                      + "read as this connection having gone")
    }
}
