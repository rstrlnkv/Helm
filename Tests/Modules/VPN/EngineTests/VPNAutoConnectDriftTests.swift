// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import XCTest
@testable import Module_VPN_Engine

/// `VPNAutoConnectCore` documents itself as emitting connect/disconnect "on the
/// 0↔1 transitions". `appLaunched` honours that — a launch already on record
/// in `launched` returns at its guard, so a second launch of the same app is
/// silent, and `wasEmpty`, captured before inserting, connects only on 0→1.
/// `appTerminated`
/// keeps it too: a quit with no launch on record in `launched` returns before
/// it touches a set, so a 0→0 event fires nothing.
///
/// That is not a theoretical event. `VPNEngine.appsChangedNow()` diffs
/// `NSWorkspace.runningApplications` against a remembered set and sends the core
/// every quit, whether or not a rule covers it at that moment — so a rule that
/// reaches the core while its app is already running produces a quit with no
/// matching launch, unless `activate()` replays a launch for that app first: the
/// user adds a rule from the settings page for an app that is open.
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

    /// Launch and quit are both idempotent: a second quit finds no record in
    /// `launched` and disconnects nothing, whatever the framework repeats. It
    /// makes no promise that a `runningApplications` change notification comes
    /// exactly once.
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

    /// Trap: `rules` is a `var` that `VPNEngine.reloadRulesNow` overwrites, while
    /// `running` stays keyed by the *old* VPN name. After a remap `rules` and
    /// `running` name two different VPNs; `appTerminated` undoes the rule
    /// recorded in `launched`, so the old VPN is not stranded and the quit does
    /// not land on the new one.
    func test_remapping_a_running_app_neither_strands_the_old_vpn_nor_cuts_the_new_one() {
        var core = VPNAutoConnectCore(rules: ["a": VPNAppRule(vpnName: "Work")])
        core.appLaunched("a", connect: { _ in })

        // The user re-points the rule at another VPN while the app keeps running.
        core.rules = ["a": VPNAppRule(vpnName: "Home")]

        var disconnects: [String] = []
        core.appTerminated("a", disconnect: { disconnects.append($0) })

        XCTAssertEqual(disconnects, ["Work"],
                       "the quit must take down the VPN the launch raised, and no other")
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
