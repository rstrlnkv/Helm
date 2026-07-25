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
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps())

        engine.toggleDefault()

        XCTAssertTrue(runner.issued.contains(["--nc", "start", "A"]))
    }

    func test_toggle_disconnects_when_connected() {
        let runner = FakeRunner()
        runner.listOutput = "(Connected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let engine = VPNEngine(settings: makeSettings(), runner: runner, apps: FakeApps())

        engine.toggleDefault()

        XCTAssertTrue(runner.issued.contains(["--nc", "stop", "A"]))
    }

    func test_connect_with_credentials_appends_secret_args() {
        let runner = FakeRunner()
        let creds = FakeCreds()
        creds.map["A"] = VPNCredentials(user: "u", password: "p", secret: "s")
        let engine = VPNEngine(settings: makeSettings(), runner: runner, credentials: creds, apps: FakeApps())

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
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps)

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
        let engine = VPNEngine(settings: settings, runner: runner, apps: apps)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        apps.bundleIDs = []
        apps.fire()

        XCTAssertTrue(runner.issued.contains(["--nc", "stop", "A"]))
    }

    // MARK: - Settle polling (spinner stuck in .connecting)

    func test_needsPoll_true_while_transitioning() {
        XCTAssertTrue(VPNEngine.needsPoll([VPNConnection(id: "1", name: "A", status: .connecting, kind: nil)]))
        XCTAssertTrue(VPNEngine.needsPoll([VPNConnection(id: "1", name: "A", status: .disconnecting, kind: nil)]))
    }

    func test_needsPoll_false_when_settled() {
        XCTAssertFalse(VPNEngine.needsPoll([VPNConnection(id: "1", name: "A", status: .connected, kind: nil),
                                            VPNConnection(id: "2", name: "B", status: .disconnected, kind: nil)]))
        XCTAssertFalse(VPNEngine.needsPoll([]))
    }
}
