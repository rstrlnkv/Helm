// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import HelmRuntime

/// One per-app auto-VPN rule: which VPN the app maps to, and what Helm does on
/// the app's launch and quit.
public struct VPNAppRule: Codable, Equatable {
    public var vpnName: String
    public var connectOnLaunch: Bool
    public var disconnectOnQuit: Bool
    /// What the app the person picked is **signed** as.
    ///
    /// The rule used to be a bundle identifier and nothing else, which is a string
    /// in a plist anybody can write: a bundle carrying a mapped identifier could
    /// launch and quit and take somebody's tunnel down. `VPNRuleTrust` is what
    /// reads this; it is optional because rules written before it existed have no
    /// identity, and that is a state with its own answer rather than a default.
    public var identity: CodeIdentity?

    public init(vpnName: String, connectOnLaunch: Bool = true, disconnectOnQuit: Bool = true,
                identity: CodeIdentity? = nil) {
        self.vpnName = vpnName
        self.connectOnLaunch = connectOnLaunch
        self.disconnectOnQuit = disconnectOnQuit
        self.identity = identity
    }

    /// The four states the two flags can express, named as the row reads.
    /// A rule with neither is inert, and saying "off" out loud beats leaving
    /// two switches that look set to something.
    public enum Timing: String, CaseIterable, Sendable {
        case launchAndQuit, launchOnly, quitOnly, off
    }

    public var timing: Timing {
        switch (connectOnLaunch, disconnectOnQuit) {
        case (true, true): .launchAndQuit
        case (true, false): .launchOnly
        case (false, true): .quitOnly
        case (false, false): .off
        }
    }

    public mutating func set(_ timing: Timing) {
        connectOnLaunch = timing == .launchAndQuit || timing == .launchOnly
        disconnectOnQuit = timing == .launchAndQuit || timing == .quitOnly
    }
}

/// Pure encode/decode/validation of the per-app auto-VPN rules
/// (bundleID → rule). The JSON goes through `VPNSettings.rulesJSON`, which is
/// where the key lives; `DefaultsKey`, named here for a while, never existed.
public enum VPNRules {
    public static func encode(_ rules: [String: VPNAppRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// Decodes the current format; a legacy `[bundleID: vpnName]` string map
    /// (the first release of the rules) migrates with both behaviors enabled.
    public static func decode(_ json: String) -> [String: VPNAppRule] {
        guard let data = json.data(using: .utf8) else { return [:] }
        if let rules = try? JSONDecoder().decode([String: VPNAppRule].self, from: data) {
            return rules
        }
        if let legacy = try? JSONDecoder().decode([String: String].self, from: data) {
            return legacy.mapValues { VPNAppRule(vpnName: $0) }
        }
        return [:]
    }

    /// The rules after somebody picked apps in the panel, which is the only place
    /// an identity is recorded.
    ///
    /// **Picking an app that already has a rule is how a rule from before
    /// identities existed is repaired.** It used to be ignored outright (`where
    /// rules[bundleID] == nil`), so «choose the app again» — which is what the row
    /// under such a rule now says — was advice the page had no way to carry out.
    /// The identity is written and every choice the person made is left as it was.
    ///
    /// A bundle whose signature could not be read at all gets no rule: a rule that
    /// can never fire is worse than no rule, because it looks like one that does.
    public static func adopting(_ picked: [(bundleID: String, identity: CodeIdentity?)],
                                into rules: [String: VPNAppRule],
                                defaultVPN: String) -> [String: VPNAppRule] {
        var updated = rules
        for app in picked {
            guard let identity = app.identity else { continue }
            if var existing = updated[app.bundleID] {
                existing.identity = identity
                updated[app.bundleID] = existing
            } else {
                updated[app.bundleID] = VPNAppRule(vpnName: defaultVPN, identity: identity)
            }
        }
        return updated
    }

    /// Drop rules whose VPN is not among the currently-configured connections.
    public static func valid(_ rules: [String: VPNAppRule], against connections: [VPNConnection]) -> [String: VPNAppRule] {
        let names = Set(connections.map(\.name))
        return rules.filter { names.contains($0.value.vpnName) }
    }

    /// How many rules can fire — what a dial labelled *automatic* is counting.
    ///
    /// It used to count `autoConnected`, the connections a rule has up at this
    /// instant, so the strip read "0" directly above the list of rules the
    /// person had written. Whether one is firing right now is the green dot's
    /// answer; this is the other question. A rule set to `.off` is written down
    /// and inert, and counting it would be the same lie the other way round.
    public static func automationCount(_ rules: [String: VPNAppRule]) -> Int {
        rules.values.count { $0.timing != .off }
    }

    /// Rules naming a VPN the system no longer has. They stop firing the
    /// moment a connection is renamed or removed, and dropping them quietly
    /// is how someone ends up trusting automation that has not run for weeks.
    public static func orphaned(_ rules: [String: VPNAppRule],
                                against connections: [VPNConnection]) -> [String: VPNAppRule] {
        let names = Set(connections.map(\.name))
        return rules.filter { !names.contains($0.value.vpnName) }
    }

}
