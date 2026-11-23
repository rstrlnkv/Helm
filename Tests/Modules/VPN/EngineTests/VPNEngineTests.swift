// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// Past defect: commit 7851a0c2, «fix(vpn): the tool is asked before the app announces, and a name stops standing in for an identity» (the settle poll ended before the tunnel began to come up).
final class VPNEngineTests: XCTestCase {
    func test_auto_connect_on_app_launch() {
        let runner = FakeRunner(list: "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\"")
        let settings = VPNSettings.inMemory()
        settings.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        apps.bundleIDs = []
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]))
        XCTAssertTrue(engine.autoConnected.contains("A"))
    }

    /// M106: deactivation stops the app observation too, and activating again
    /// arms it once.
    func test_deactivate_stops_the_app_observation() {
        let apps = FakeApps.trustingA()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: FakeRunner(), apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        XCTAssertEqual(apps.starts, 1)
        engine.deactivate()
        XCTAssertEqual(apps.stops, 1)
        XCTAssertNil(apps.onChange)

        engine.activate()
        XCTAssertEqual(apps.starts, 2)
        XCTAssertNotNil(apps.onChange)
    }

    /// M106: an engine released without `deactivate()` still stops the app observation.
    func test_deinit_stops_the_app_observation() {
        let apps = FakeApps.trustingA()
        var engine: VPNEngine? = VPNEngine(settings: VPNSettings.inMemory(), runner: FakeRunner(), apps: apps,
                                           interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                                           work: .inline)
        engine?.activate()
        XCTAssertNotNil(apps.onChange)

        engine = nil

        XCTAssertEqual(apps.stops, 1)
        XCTAssertNil(apps.onChange)
    }

    func test_auto_disconnect_on_app_quit() {
        let runner = FakeRunner(list: "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\"")
        let settings = VPNSettings.inMemory()
        settings.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        apps.bundleIDs = []
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        apps.bundleIDs = []
        apps.fire()

        XCTAssertTrue(runner.issued.contains(["--nc", "stop", "A"]))
    }

    // MARK: - Settle polling (the card stuck on the status the command replaced)

    /// The exit condition, in place of the two `needsPoll` tests that stood here.
    /// It asked «is anything transitioning», and `Disconnected` is not a
    /// transition — so the first read after a connect ended the poll before the
    /// tunnel had begun to come up. It asks whether the command has arrived now.
    func test_a_poll_is_not_over_while_the_command_it_follows_has_not_arrived() {
        let coming = [VPNConnection(id: "1", name: "A", status: .connecting, kind: nil)]
        XCTAssertFalse(VPNEngine.settled(coming, into: .connected, for: "A"))
        // What the tool says while it has not caught up yet, which is the whole
        // reason the poll exists — and the same list is the answer to a stop.
        let notYet = [VPNConnection(id: "1", name: "A", status: .disconnected, kind: nil)]
        XCTAssertFalse(VPNEngine.settled(notYet, into: .connected, for: "A"))
        XCTAssertTrue(VPNEngine.settled(notYet, into: .disconnected, for: "A"))
    }

    func test_a_poll_is_over_when_the_connection_it_asked_about_arrives() {
        let list = [VPNConnection(id: "1", name: "A", status: .connected, kind: nil),
                    VPNConnection(id: "2", name: "B", status: .disconnected, kind: nil)]
        XCTAssertTrue(VPNEngine.settled(list, into: .connected, for: "A"))
        // Another connection reaching that state is not this command's answer,
        // and a list with nothing in it is nobody's.
        XCTAssertFalse(VPNEngine.settled(list, into: .connected, for: "B"))
        XCTAssertFalse(VPNEngine.settled([], into: .connected, for: "A"))
    }
}
