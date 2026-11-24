// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// A tunnel connected or disconnected from the macOS menu bar or from System
/// Settings, or dropped, never comes back through Helm, so the engine watches
/// the system's own network state and re-reads on it. These tests assert on
/// the *structure* — that something is watching, that it stops, and that a
/// change reaches `scutil` — rather than on a settled value, which a poll
/// already schedules and could satisfy by luck.
final class VPNNetworkWatchTests: XCTestCase {
    func testActivateStartsWatchingTheNetwork() {
        let network = FakeNetwork()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: FakeRunner(),
                               apps: FakeApps(), network: network,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()

        XCTAssertEqual(network.starts, 1)
    }

    func testAChangeInTheNetworkReReadsTheList() {
        let runner = FakeRunner()
        let network = FakeNetwork()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: runner,
                               apps: FakeApps(), network: network,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
        engine.activate()
        let before = runner.issued.filter { $0 == ["--nc", "list"] }.count

        network.fire()

        XCTAssertEqual(runner.issued.filter { $0 == ["--nc", "list"] }.count, before + 1,
                       "a tunnel raised or dropped outside Helm left the dot as it was")
    }

    /// The host calls `deactivate()` and then drops the engine, so anything
    /// still pointing at it points at freed memory
    /// (Architecture/StateAndLifetime.md § An observer outlives the thing it points at).
    func testDeactivateStopsWatching() {
        let network = FakeNetwork()
        let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: FakeRunner(),
                               apps: FakeApps(), network: network,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)
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
            let engine = VPNEngine(settings: VPNSettings.inMemory(), runner: FakeRunner(),
                                   apps: FakeApps(), network: network,
                                   interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                                   work: .inline)
            engine.activate()
        }
        XCTAssertEqual(network.stops, 1)
        XCTAssertNil(network.onChange)
    }
}
