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
///
/// Guards an unattended action (a rule raising a tunnel); M103 below is the
/// defect where a first unreadable list dropped every rule for good.
///
/// Past defect: commit 6dec5f2f, «fix: eight defects a second agent pass turned up».
final class VPNEngineRuleReloadTests: XCTestCase {
    /// Off and on again. The rule is present, the VPN is present, the app
    /// launches — and the second launch issues nothing.
    func test_rule_removed_and_restored_still_connects_on_the_next_launch() {
        let runner = FakeRunner(list: "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\"")
        let store = VPNSettings.inMemory()
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
        let runner = FakeRunner(list: "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\"")
        let store = VPNSettings.inMemory()
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
    /// next reload, and renamed back afterwards. `VPNTenants.orphaned` exists
    /// precisely because this happens.
    func test_vpn_renamed_away_and_back_still_connects_on_the_next_launch() {
        let runner = FakeRunner(list: "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\"")
        let store = VPNSettings.inMemory()
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

extension VPNEngineRuleReloadTests {
    /// M103: the first `--nc list` fails, so the rules cannot be filtered against
    /// the connections; the second answers, and the app already running when the
    /// engine started fires its rule once, through the identity gate.
    func test_rules_dropped_by_an_unread_list_come_back_and_replay_the_running_app() {
        let runner = FakeRunner()
        runner.failingListReads = 1
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let store = VPNSettings.inMemory()
        store.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        apps.bundleIDs = ["com.a"]
        let network = FakeNetwork()
        let engine = VPNEngine(settings: store, runner: runner, apps: apps, network: network,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        XCTAssertEqual(runner.starts(of: "A"), 0, "no list yet, so nothing can fire")
        network.fire()

        XCTAssertEqual(runner.starts(of: "A"), 1,
                       "the list is read now, the rule is back and its app has been running since before")
    }

    /// The replay is the identity gate's, not a way round it: an instance signed as
    /// something else fires nothing after the late read.
    func test_the_replay_after_a_late_list_goes_through_the_identity_gate() {
        let runner = FakeRunner()
        runner.failingListReads = 1
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let store = VPNSettings.inMemory()
        store.setRulesJSON(ruleJSONForA)
        let apps = FakeApps()
        apps.bundleIDs = ["com.a"]
        let network = FakeNetwork()
        let engine = VPNEngine(settings: store, runner: runner, apps: apps, network: network,
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        network.fire()

        XCTAssertEqual(runner.starts(of: "A"), 0)
    }

    /// The replay is for a running module only: a list read that lands after
    /// `deactivate()` applies the held rules but starts nothing.
    func test_a_late_list_read_after_deactivate_starts_no_tunnel() {
        let runner = FakeRunner()
        runner.failingListReads = 1
        runner.listOutput = "(Disconnected) 11111111-1111-1111-1111-111111111111 IPSec \"A\""
        let store = VPNSettings.inMemory()
        store.setRulesJSON(ruleJSONForA)
        let apps = FakeApps.trustingA()
        apps.bundleIDs = ["com.a"]
        let engine = VPNEngine(settings: store, runner: runner, apps: apps, network: FakeNetwork(),
                               interfaces: FakeInterfaces(), exit: FakeExit(), speed: FakeSpeed(),
                               work: .inline)

        engine.activate()
        engine.deactivate()
        engine.refresh()

        XCTAssertEqual(runner.starts(of: "A"), 0, "the module is stopped, so a late list starts nothing")
    }
}

private extension FakeRunner {
    func starts(of name: String) -> Int {
        issued.filter { $0 == ["--nc", "start", name] }.count
    }
}
