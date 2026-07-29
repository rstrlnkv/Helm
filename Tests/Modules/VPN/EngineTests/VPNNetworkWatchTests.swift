// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import HelmRuntime
@testable import Module_VPN_Engine

/// The module exists to answer one question — is a tunnel up — and it asked the
/// system once per launch. Connect or disconnect from the macOS menu bar or
/// from System Settings, or let the tunnel drop, and Helm's dot stayed as it
/// was until relaunch: a cache with no expiry standing in for the answer.
///
/// So the engine watches the system's own network state and re-reads on it.
/// These tests assert on the *structure* — that something is watching, that it
/// stops, and that a change reaches `scutil` — rather than on a settled value,
/// which a poll already schedules and could satisfy by luck.
final class VPNNetworkWatchTests: XCTestCase {
    private func settings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    func testActivateStartsWatchingTheNetwork() {
        let network = FakeNetwork()
        let engine = VPNEngine(settings: settings(), runner: FakeRunner(),
                               apps: FakeApps(), network: network, work: .inline)

        engine.activate()

        XCTAssertEqual(network.starts, 1)
    }

    func testAChangeInTheNetworkReReadsTheList() {
        let runner = FakeRunner()
        let network = FakeNetwork()
        let engine = VPNEngine(settings: settings(), runner: runner,
                               apps: FakeApps(), network: network, work: .inline)
        engine.activate()
        let before = runner.issued.filter { $0 == ["--nc", "list"] }.count

        network.fire()

        XCTAssertEqual(runner.issued.filter { $0 == ["--nc", "list"] }.count, before + 1,
                       "a tunnel raised or dropped outside Helm left the dot as it was")
    }

    /// ARCHITECTURE.md § "An observer outlives the thing it points at": the
    /// host calls `deactivate()` and then drops the engine, so anything still
    /// pointing at it is pointing at freed memory.
    func testDeactivateStopsWatching() {
        let network = FakeNetwork()
        let engine = VPNEngine(settings: settings(), runner: FakeRunner(),
                               apps: FakeApps(), network: network, work: .inline)
        engine.activate()

        engine.deactivate()

        XCTAssertEqual(network.stops, 1)
        XCTAssertNil(network.onChange, "the callback outlived the module being switched off")
    }

    /// The backstop for the routes that do not go through `deactivate()` — a
    /// view model dropped, a module rebuilt, a test that never disables.
    func testDroppingTheEngineStopsWatching() {
        let network = FakeNetwork()
        do {
            let engine = VPNEngine(settings: settings(), runner: FakeRunner(),
                                   apps: FakeApps(), network: network, work: .inline)
            engine.activate()
        }
        XCTAssertEqual(network.stops, 1)
        XCTAssertNil(network.onChange)
    }
}
