// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

final class VPNEngineTests: XCTestCase {
    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    func test_toggle_connects_default_when_disconnected() {
        let runner = FakeRunner()
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(), work: .inline)

        engine.toggleDefault()

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]))
    }

    func test_toggle_disconnects_when_connected() {
        let runner = FakeRunner()
        runner.listOutput = "(Connected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps(), work: .inline)

        engine.toggleDefault()

        XCTAssertTrue(runner.issued.contains(["--nc", "stop", "A"]))
    }

    func test_connect_with_credentials_appends_secret_args() {
        let runner = FakeRunner()
        let creds = FakeCreds()
        creds.map["A"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let engine = VPNEngine(settings: makeSettings(), runner: runner, credentials: creds, apps: FakeApps(), work: .inline)

        engine.connect("A")

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A", "--user", "u", "--password", "p", "--secret", "s"]))
    }

    func test_auto_connect_on_app_launch() {
        let runner = FakeRunner()
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let settings = makeSettings()
        settings.setRulesJSON("{\"com.a\":{\"vpnName\":\"A\",\"connectOnLaunch\":true,\"disconnectOnQuit\":true}}")
        let apps = FakeApps()
        apps.bundleIDs = []
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps, work: .inline)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]))
        XCTAssertTrue(engine.autoConnected.contains("A"))
    }

    func test_auto_disconnect_on_app_quit() {
        let runner = FakeRunner()
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let settings = makeSettings()
        settings.setRulesJSON("{\"com.a\":{\"vpnName\":\"A\",\"connectOnLaunch\":true,\"disconnectOnQuit\":true}}")
        let apps = FakeApps()
        apps.bundleIDs = []
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps, work: .inline)

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
