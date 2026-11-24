// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// **What a tunnel carries around itself instead of through itself.**
///
/// A NetworkExtension configuration declares excluded routes, and a verdict that
/// ignored them would say «Traffic goes through the tunnel» beside a connected
/// card. That sentence can be false: an exclusion of `17.0.0.0/8` sends Apple's
/// whole network — iCloud, the App Store, iMessage — out through `en0` with the
/// real address.
///
/// `VPNStatusParser` calls them «the decoys» and walks past them by indentation
/// to reach the tunnel's own interface, collecting their destinations on the way.
public enum VPNExcludedRoutes {

    /// One declared exclusion, as the tool writes it: a destination, a dotted quad.
    ///
    /// **No mask is kept, because the verdict is matched on the destination
    /// alone.** The parser still requires the `SubnetMask` line to finish a
    /// route, so a dictionary the tool cut short is dropped rather than
    /// half-read (`VPNStatusParser`).
    struct Route: Equatable, Sendable {
        let destination: String
    }

    /// **What the exclusions amount to, in the three shapes a reader can act
    /// on** — never the ranges themselves.
    ///
    /// The summary is what travels, and the addresses stay in the engine: a
    /// range is a fact about somebody's network, as an exit address is
    /// (`VPNExitPort`), and «10.0.0.0/8» tells a reader nothing that «the local
    /// network» does not.
    public struct Summary: Equatable, Sendable {
        /// Private ranges, link-local, multicast, broadcast — the exclusions
        /// nearly every tunnel declares so that printers and NAS boxes keep
        /// working.
        public let localNetwork: Bool
        /// `17.0.0.0/8`. Its own case rather than one of `others`, because it
        /// is the one exclusion a person would want to know about by name: it
        /// is not a printer, it is every Apple service this Mac talks to.
        public let apple: Bool
        /// Anything else, counted rather than flagged, because «two more» and
        /// «forty more» are different news.
        public let others: Int

        /// The tunnel that excludes nothing. Not the same as «nobody looked» —
        /// a status read that failed produces no `Reading` at all, so there is
        /// no third state to represent here.
        static let none = Summary(localNetwork: false, apple: false, others: 0)
    }

    /// Apple's network, as one `/8`.
    static let appleNetwork = "17.0.0.0"

    /// The ranges a tunnel excludes to leave the local network reachable.
    ///
    /// Matched on the destination alone. The masks a configuration writes for
    /// these vary, and a tunnel that excludes 10/8 with an unusual mask has
    /// still excluded the local network, which is all this word claims.
    static let localRanges: Set<String> = [
        "10.0.0.0",         // RFC 1918
        "172.16.0.0",       // RFC 1918
        "192.168.0.0",      // RFC 1918
        "169.254.0.0",      // link-local
        "224.0.0.0",        // multicast
        "255.255.255.255",  // broadcast
    ]

    static func summarize(_ routes: [Route]) -> Summary {
        var localNetwork = false
        var apple = false
        var others = 0
        for route in routes {
            if localRanges.contains(route.destination) { localNetwork = true }
            else if route.destination == appleNetwork { apple = true }
            else { others += 1 }
        }
        return Summary(localNetwork: localNetwork, apple: apple, others: others)
    }
}
