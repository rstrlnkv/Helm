// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// `VPNAutoConnectCore` documents itself as emitting connect/disconnect "on the
/// 0↔1 transitions". `appLaunched` honours that — it captures `wasEmpty` before
/// inserting, so a second launch of the same app is silent. `appTerminated`
/// does not: it removes, then asks whether the set is *now* empty, without ever
/// asking whether the removal changed anything. A set that was already empty is
/// still empty afterwards, so a 0→0 event fires disconnect.
///
/// That is not a theoretical event. `VPNEngine.appsChanged()` diffs
/// `NSWorkspace.runningApplications` against a remembered set and only forwards
/// ids that have a rule *at that moment* — so any path that gives an app a rule
/// while it is already running produces a quit with no matching launch:
/// the user adds a rule from the settings page for an app that is open, or
/// `reloadRules()` re-reads the rules after a `refresh()` renames a connection.
final class VPNAutoConnectDriftTests: XCTestCase {

    /// The 0→0 case, minimal. Helm never connected this VPN, so it must not
    /// take one down — the user may have dialled it up by hand.
    func test_quit_without_a_prior_launch_does_not_disconnect() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V")])
        var disconnects: [String] = []
        core.appTerminated("a", disconnect: { disconnects.append($0) })
        XCTAssertEqual(disconnects, [],
                       "a quit with no matching launch tore down a VPN Helm never raised")
    }

    /// The same defect seen as an asymmetry: launch is idempotent, quit is not.
    /// One extra `runningApplications` change notification — the framework makes
    /// no promise of exactly-once — costs the user their connection twice.
    func test_repeated_quit_disconnects_at_most_once() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V")])
        var connects: [String] = [], disconnects: [String] = []
        core.appLaunched("a", connect: { connects.append($0) })
        core.appLaunched("a", connect: { connects.append($0) })
        XCTAssertEqual(connects, ["V"], "launch is already idempotent")

        core.appTerminated("a", disconnect: { disconnects.append($0) })
        core.appTerminated("a", disconnect: { disconnects.append($0) })
        XCTAssertEqual(disconnects, ["V"], "quit is not idempotent the way launch is")
    }

    /// Trap: `rules` is a `var` that `VPNEngine.reloadRules()` overwrites, while
    /// `running` stays keyed by the *old* VPN name. After a remap the bookkeeping
    /// points at two different VPNs: the old one is stranded as permanently
    /// active, and the quit lands on the new one, which was never connected.
    func test_remapping_a_running_app_neither_strands_the_old_vpn_nor_cuts_the_new_one() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "Work")])
        core.appLaunched("a", connect: { _ in })
        XCTAssertEqual(core.activeVPNs, ["Work"])

        // The user re-points the rule at another VPN while the app keeps running.
        core.rules = ["a": VPNAppRule(vpnName: "Home")]

        var disconnects: [String] = []
        core.appTerminated("a", disconnect: { disconnects.append($0) })

        XCTAssertFalse(disconnects.contains("Home"),
                       "quitting the app disconnected a VPN it was never launched against")
        XCTAssertTrue(core.activeVPNs.isEmpty,
                      "the old VPN is stranded as active forever: \(core.activeVPNs)")
    }

    /// Guard against the obvious over-correction: a real 1→0 transition must
    /// still disconnect, and the existing shared-VPN counting must survive.
    func test_a_real_last_quit_still_disconnects() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "V"),
                                              "b": VPNAppRule(vpnName: "V")])
        var disconnects: [String] = []
        core.appLaunched("a", connect: { _ in })
        core.appLaunched("b", connect: { _ in })
        core.appTerminated("a", disconnect: { disconnects.append($0) })
        XCTAssertEqual(disconnects, [])
        core.appTerminated("b", disconnect: { disconnects.append($0) })
        XCTAssertEqual(disconnects, ["V"])
    }

    /// A rule with `disconnectOnQuit` off must stay silent on every path,
    /// including the unmatched-quit one above.
    func test_quit_flag_off_is_silent_even_without_a_launch() {
        var core = VPNAutoConnectCore(
            rules: ["a": VPNAppRule(vpnName: "V", connectOnLaunch: true, disconnectOnQuit: false)])
        var disconnects: [String] = []
        core.appTerminated("a", disconnect: { disconnects.append($0) })
        XCTAssertEqual(disconnects, [])
    }
}
