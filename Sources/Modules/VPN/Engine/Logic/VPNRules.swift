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
