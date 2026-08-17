// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
import HelmRuntime
@testable import Module_VPN_Engine

/// What a reload of the rules does to apps that are already running.
///
/// `VPNAutoConnectCore` keeps two books: `rules`, which the settings page
/// overwrites whenever anything is saved, and `launched`, which records the
/// rule that was in force when an app was counted as running. Its own doc
/// comment says why — "`rules` … cannot be trusted to say what a quit should
/// undo" — and `appTerminated` is written to consult `launched` alone.
///
/// `VPNEngine.appsChangedNow` then filters both halves of the diff through the
/// *current* rules:
///
///     for id in quit where core.rules[id] != nil { core.appTerminated(id, …) }
///
/// which puts the untrustworthy book back in front of the trustworthy one. When
/// the rule for a running app disappears between its launch and its quit — the
/// user turns the rule off, or `VPNRules.valid` drops it because the VPN was
/// renamed — the quit never reaches the core. `launched[bundleID]` is never
/// cleared, and `appLaunched` refuses to act on any app it believes is already
/// launched. Auto-connect for that app is dead for the rest of the session,
/// with a rule on screen that says it is on.
final class VPNEngineRuleReloadTests: XCTestCase {
    private func settings() -> VPNSettings {
        VPNSettings(store: NamespacedStore(namespace: "vpn", backing: InMemoryKeyValueStore()))
    }

    /// Off and on again. The rule is present, the VPN is present, the app
    /// launches — and the second launch issues nothing.
    func test_rule_removed_and_restored_still_connects_on_the_next_launch() {
        let runner = FakeRunner()
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let store = settings()
        store.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        let engine = VPNEngine(settings: store, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        XCTAssertEqual(runner.starts(of: "A"), 1, "the first launch connects")

        // The user switches the rule off in the settings page, which persists
        // and asks the engine to reload.
        store.setRulesJSON("{}")
        engine.reloadRules()
        // …and quits the app while it is off.
        apps.bundleIDs = []
        apps.fire()
        // …then switches the rule back on.
        store.setRulesJSON(ruleJSONForA)
        engine.reloadRules()

        // A live rule, a configured VPN, and the app launches again.
        apps.bundleIDs = ["com.a"]
        apps.fire()

        XCTAssertEqual(runner.starts(of: "A"), 2,
                       "the rule is on and the app launched, so the VPN must be raised again")
    }

    /// The control, and it passes today: the same sequence with the quit
    /// arriving while the rule is still in force reconnects on the next launch.
    /// The difference between this test and the one above is the quit landing
    /// inside the window where `core.rules` has no entry — which is what pins
    /// the failure on the `where core.rules[id] != nil` filter rather than on
    /// the reload or on the fake.
    func test_control_a_quit_while_the_rule_is_live_reconnects_on_relaunch() {
        let runner = FakeRunner()
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let store = settings()
        store.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        let engine = VPNEngine(settings: store, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        apps.bundleIDs = []
        apps.fire()
        store.setRulesJSON("{}")
        engine.reloadRules()
        store.setRulesJSON(ruleJSONForA)
        engine.reloadRules()
        apps.bundleIDs = ["com.a"]
        apps.fire()

        XCTAssertEqual(runner.starts(of: "A"), 2)
    }

    /// The same shape with nobody touching the rules: the connection is
    /// renamed in System Settings, so `VPNRules.valid` drops the rule at the
    /// next reload, and renamed back afterwards. `orphaned` exists precisely
    /// because this happens.
    func test_vpn_renamed_away_and_back_still_connects_on_the_next_launch() {
        let runner = FakeRunner()
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let store = settings()
        store.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        let engine = VPNEngine(settings: store, runner: runner, apps: apps,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        apps.bundleIDs = ["com.a"]
        apps.fire()
        XCTAssertEqual(runner.starts(of: "A"), 1)

        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"Work\""
        engine.reloadRules()
        apps.bundleIDs = []
        apps.fire()

        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        engine.reloadRules()
        apps.bundleIDs = ["com.a"]
        apps.fire()

        XCTAssertEqual(runner.starts(of: "A"), 2,
                       "the connection is back under its old name and the app launched again")
    }
}

private extension FakeRunner {
    func starts(of name: String) -> Int {
        issued.filter { $0 == ["--nc", "start", name] }.count
    }
}
