// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// One per-app auto-VPN rule: which VPN the app maps to, and what Helm does on
/// the app's launch and quit.
public struct VPNAppRule: Codable, Equatable {
    public var vpnName: String
    public var connectOnLaunch: Bool
    public var disconnectOnQuit: Bool

    public init(vpnName: String, connectOnLaunch: Bool = true, disconnectOnQuit: Bool = true) {
        self.vpnName = vpnName
        self.connectOnLaunch = connectOnLaunch
        self.disconnectOnQuit = disconnectOnQuit
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
/// (bundleID → rule), stored as JSON in DefaultsKey.vpnAppRules.
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

    /// Drop rules whose VPN is not among the currently-configured connections.
    public static func valid(_ rules: [String: VPNAppRule], against connections: [VPNConnection]) -> [String: VPNAppRule] {
        let names = Set(connections.map(\.name))
        return rules.filter { names.contains($0.value.vpnName) }
    }
}
