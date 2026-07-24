// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Pure reference-counting for per-app auto-VPN. Holds which mapped apps are
/// running per VPN; on the 0↔1 transitions it emits connect/disconnect,
/// honoring each rule's per-behavior flags. No AppKit — driven by app
/// launch/quit events and validated in unit tests.
public struct VPNAutoConnectCore {
    /// bundleID → rule.
    public var rules: [String: VPNAppRule]
    /// VPN name → set of running mapped bundleIDs.
    private var running: [String: Set<String>] = [:]

    public init(rules: [String: VPNAppRule]) { self.rules = rules }

    public mutating func appLaunched(_ bundleID: String,
                              connect: (String) -> Void,
                              disconnect: (String) -> Void) {
        guard let rule = rules[bundleID] else { return }
        var set = running[rule.vpnName] ?? []
        let wasEmpty = set.isEmpty
        set.insert(bundleID)
        running[rule.vpnName] = set
        if wasEmpty && rule.connectOnLaunch { connect(rule.vpnName) }
    }

    public mutating func appTerminated(_ bundleID: String,
                                connect: (String) -> Void,
                                disconnect: (String) -> Void) {
        guard let rule = rules[bundleID] else { return }
        var set = running[rule.vpnName] ?? []
        set.remove(bundleID)
        running[rule.vpnName] = set
        if set.isEmpty && rule.disconnectOnQuit { disconnect(rule.vpnName) }
    }

    /// The VPNs with ≥1 mapped app currently running.
    public var activeVPNs: Set<String> {
        Set(running.filter { !$0.value.isEmpty }.keys)
    }
}
