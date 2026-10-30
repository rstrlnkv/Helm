// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation
import SystemConfiguration

/// The dictionary `SCNetworkConnectionStart` takes in place of `--user`,
/// `--password` and `--secret`: pure, so what each kind of tunnel is handed is
/// written down once and tested without a system to start anything. The keys
/// are the ones `scutil`'s own `nc_start` puts there (read from its machine
/// code: `otool -arch arm64e -tV /usr/sbin/scutil | grep -B160
/// _SCNetworkConnectionStart`), not the ones a header suggests.
enum VPNStartOptions {

    // A plugin VPN's names are private to SystemConfiguration's headers, though
    // the symbols are exported; these are their values as the system holds them
    // (`kSCNetworkInterfaceTypeVPN`, `kSCEntNetVPN`, `kSCPropNetVPNAuthName`,
    // `kSCPropNetVPNAuthPassword`, read through `dlsym`).
    private static let pluginType = "VPN"
    private static let pluginEntity = "VPN"
    private static let pluginAuthName = "AuthName"
    private static let pluginAuthPassword = "AuthPassword"

    /// - Parameter interface: the type of the service's own interface — `PPP`,
    ///   `IPSec` (Cisco), or `VPN` (a plugin).
    /// - Parameter inner: the type of the interface under a PPP one, `L2TP` when
    ///   the PPP service carries L2TP; nil when there is none.
    /// - Returns: nil for a type this build does not know, which is a start without
    ///   options rather than a guess at their keys. Empty fields are left out.
    static func userOptions(_ creds: VPNCredentials, interface: String,
                            inner: String?) -> [String: [String: String]]? {
        func present(_ value: String?) -> String? { value.flatMap { $0.isEmpty ? nil : $0 } }
        func entry(_ pairs: [(String, String?)]) -> [String: String] {
            var out: [String: String] = [:]
            for (key, value) in pairs { if let value = present(value) { out[key] = value } }
            return out
        }
        var options: [String: [String: String]] = [:]
        let ppp = kSCNetworkInterfaceTypePPP as String
        let cisco = kSCNetworkInterfaceTypeIPSec as String
        let isL2TP = interface == ppp && inner == kSCValNetInterfaceSubTypeL2TP as String
        switch interface {
        case ppp:
            let login = entry([(kSCPropNetPPPAuthName as String, creds.user),
                               (kSCPropNetPPPAuthPassword as String, creds.password)])
            if !login.isEmpty { options[kSCEntNetPPP as String] = login }
        case cisco:
            break
        case Self.pluginType:
            let login = entry([(Self.pluginAuthName, creds.user),
                               (Self.pluginAuthPassword, creds.password)])
            if !login.isEmpty { options[Self.pluginEntity] = login }
        default:
            return nil
        }
        // IPSec's entry: Cisco IPSec adds the XAuth login, L2TP only the secret.
        if interface == cisco || isL2TP {
            let ipsec = entry([(kSCPropNetIPSecXAuthName as String, isL2TP ? nil : creds.user),
                               (kSCPropNetIPSecXAuthPassword as String, isL2TP ? nil : creds.password),
                               (kSCPropNetIPSecSharedSecret as String, creds.secret)])
            if !ipsec.isEmpty { options[kSCEntNetIPSec as String] = ipsec }
        }
        return options
    }
}
