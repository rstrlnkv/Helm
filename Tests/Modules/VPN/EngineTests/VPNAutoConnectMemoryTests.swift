// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// `_cameUp` — the set added today so `refreshNow` can tell "not up yet" from
/// "came up and then went" — is filled by `refreshNow` and emptied by
/// `refreshNow`. Nothing else touches it.
///
/// `disconnectNow` empties `_autoConnected` and leaves `_cameUp` holding the
/// name. The two sets are then out of step, and the next time Helm raises the
/// same VPN the first refresh after the connect — the one whose whole reason
/// for existing is that it "usually still reports the old status" — reads
/// `_autoConnected \ up ∩ _cameUp` as `{name}` and forgets that Helm raised it.
///
/// Asserted on the engine's own record rather than on a rendered number: what
/// `autoConnected` is *for* is answering "did Helm raise this", and the page's
/// AUTOMATIC count is one reader of it.
final class VPNAutoConnectMemoryTests: XCTestCase {

    private func makeSettings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    private let uuid = "11111111-1111-1111-1111-111111111111"
    private func list(_ status: String) -> String {
        "(\(status)) \(uuid) IPSec \"A\""
    }

    /// The second session with the same app. Launch → connect → up → quit →
    /// disconnect → launch again. At the end Helm has just issued `--nc start`
    /// itself, so it must still know the connection is its own.
    func test_a_vpn_raised_a_second_time_is_still_its_own() {
        let runner = FakeRunner()
        let engine = VPNEngine(settings: makeSettings(), runner: runner,
                               apps: FakeApps(), work: .inline)

        // First session: Helm raises it, and a later refresh sees it up.
        runner.listOutput = list("Disconnected")
        engine.connect("A", auto: true)
        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "a connect Helm has just issued is Helm's, whatever scutil still says")
        runner.listOutput = list("Connected")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("A"))

        // The app quits: Helm takes its own connection down.
        runner.listOutput = list("Disconnected")
        engine.disconnect("A")
        XCTAssertFalse(engine.autoConnected.contains("A"),
                       "a connection Helm dropped is no longer Helm's")

        // The app launches again. `scutil --nc start` is asynchronous, so the
        // refresh that follows still reports Disconnected — the case the whole
        // `_cameUp` mechanism was added to survive.
        engine.connect("A", auto: true)

        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "Helm forgot a VPN it had just raised, because the memory of the "
                      + "previous session's `came up` was never cleared when it "
                      + "disconnected: autoConnected = \(engine.autoConnected)")
    }

    /// The behaviour the day's change exists for, so a fix cannot buy the test
    /// above by simply never forgetting anything: a connection Helm raised,
    /// that came up and then dropped on its own, stops being Helm's.
    func test_a_vpn_that_came_up_and_then_went_is_forgotten() {
        let runner = FakeRunner()
        let engine = VPNEngine(settings: makeSettings(), runner: runner,
                               apps: FakeApps(), work: .inline)

        runner.listOutput = list("Disconnected")
        engine.connect("A", auto: true)
        runner.listOutput = list("Connected")
        engine.refresh()
        XCTAssertTrue(engine.autoConnected.contains("A"))

        // The network went, or somebody stopped it in System Settings.
        runner.listOutput = list("Disconnected")
        engine.refresh()

        XCTAssertFalse(engine.autoConnected.contains("A"),
                       "a connection that came up and then went is not up any more")
    }

    /// And the case that mechanism protects: a connect whose status has not
    /// caught up yet must survive any number of refreshes before it does.
    func test_a_vpn_that_has_not_come_up_yet_is_not_forgotten() {
        let runner = FakeRunner()
        let engine = VPNEngine(settings: makeSettings(), runner: runner,
                               apps: FakeApps(), work: .inline)

        runner.listOutput = list("Disconnected")
        engine.connect("A", auto: true)
        engine.refresh()
        engine.refresh()

        XCTAssertTrue(engine.autoConnected.contains("A"),
                      "a connection Helm asked for and that has not answered yet is still Helm's")
    }
}
