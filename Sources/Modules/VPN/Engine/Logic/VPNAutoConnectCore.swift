// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Pure reference-counting for per-app auto-VPN. Holds which mapped apps are
/// running per VPN; on the 0↔1 transitions it emits connect/disconnect,
/// honoring each rule's per-behavior flags. No AppKit — driven by app
/// launch/quit events and validated in unit tests.
struct VPNAutoConnectCore {
    /// bundleID → rule.
    var rules: [String: VPNAppRule]
    /// VPN name → set of running mapped bundleIDs.
    private var running: [String: Set<String>] = [:]
    /// bundleID → the rule that was in force when it was counted as running.
    ///
    /// `rules` is overwritten whenever the settings page saves or a refresh
    /// renames a connection, so it cannot be trusted to say what a quit should
    /// undo: the app may have been launched against a different VPN, or against
    /// no rule at all. Only what is recorded here was actually raised by Helm.
    private var launched: [String: VPNAppRule] = [:]

    init(rules: [String: VPNAppRule]) { self.rules = rules }

    mutating func appLaunched(_ bundleID: String,
                              connect: (String) -> Void,
                              disconnect: (String) -> Void) {
        guard let rule = rules[bundleID], launched[bundleID] == nil else { return }
        var set = running[rule.vpnName] ?? []
        let wasEmpty = set.isEmpty
        set.insert(bundleID)
        running[rule.vpnName] = set
        launched[bundleID] = rule
        if wasEmpty && rule.connectOnLaunch { connect(rule.vpnName) }
    }

    mutating func appTerminated(_ bundleID: String,
                                connect: (String) -> Void,
                                disconnect: (String) -> Void) {
        // No launch on record means Helm did not raise this VPN — the user may
        // have dialled it up by hand, and a quit must not take it down.
        guard let rule = launched.removeValue(forKey: bundleID) else { return }
        var set = running[rule.vpnName] ?? []
        set.remove(bundleID)
        running[rule.vpnName] = set
        if set.isEmpty && rule.disconnectOnQuit { disconnect(rule.vpnName) }
    }

    /// The VPNs with ≥1 mapped app currently running.
    var activeVPNs: Set<String> {
        Set(running.filter { !$0.value.isEmpty }.keys)
    }
}
