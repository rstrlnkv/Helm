// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// **What a tunnel carries around itself instead of through itself.**
///
/// A NetworkExtension configuration declares excluded routes, and the page said
/// nothing about them while telling the reader, under a green tick, that «all of
/// this Mac's traffic goes through the VPN». On the machine this was written
/// against that sentence is false: among the seven exclusions is `17.0.0.0/8`,
/// which is Apple's whole network — iCloud, the App Store, iMessage — leaving
/// through `en0` with the real address.
///
/// Helm was already reading these lines and throwing them away.
/// `VPNStatusParser` calls them «the decoys» and walks past them by indentation
/// to reach the tunnel's own interface, and seven of them sit in that parser's
/// own committed fixture. The verdict was built out of the one line the walk was
/// looking for and none of the ones it stepped over.
public enum VPNExcludedRoutes {

    /// One declared exclusion, as the tool writes it: a destination and a mask,
    /// both dotted quads.
    public struct Route: Equatable, Sendable {
        public let destination: String
        public let mask: String
        public init(destination: String, mask: String) {
            self.destination = destination
            self.mask = mask
        }
    }

    /// **What the exclusions amount to, in the three shapes a reader can act
    /// on** — never the ranges themselves.
    ///
    /// The summary is what travels, and the addresses stay in the engine. A
    /// range is not a name, but it is a fact about somebody's network, and this
    /// module already refuses to put an exit address on the wire for the same
    /// reason (`VPNExitPort`). It is also what a reader can do anything with:
    /// «and 10.0.0.0/8» tells them nothing that «the local network» does not.
    public struct Summary: Codable, Equatable, Sendable {
        /// Private ranges, link-local, multicast, broadcast — the exclusions
        /// nearly every tunnel declares so that printers and NAS boxes keep
        /// working. True of a dull configuration and worth one word.
        public let localNetwork: Bool
        /// `17.0.0.0/8`. Its own case rather than one of `others`, because it
        /// is the one exclusion a person would want to know about by name: it
        /// is not a printer, it is every Apple service this Mac talks to.
        public let apple: Bool
        /// Anything else, counted. Named by number rather than by range for the
        /// reason the type's own comment gives — and counted rather than
        /// flagged, because «two more» and «forty more» are different news.
        public let others: Int

        public init(localNetwork: Bool, apple: Bool, others: Int) {
            self.localNetwork = localNetwork
            self.apple = apple
            self.others = others
        }

        /// The tunnel that excludes nothing. Not the same as «nobody looked» —
        /// a status read that failed produces no `Reading` at all, so there is
        /// no third state to represent here.
        public static let none = Summary(localNetwork: false, apple: false, others: 0)
        public var isEmpty: Bool { self == .none }
    }

    /// Apple's network, as one `/8`. A constant with its own name because the
    /// number means nothing on sight and a reader should not have to look it up.
    static let appleNetwork = "17.0.0.0"

    /// The ranges a tunnel excludes to leave the local network reachable.
    ///
    /// Matched on the destination alone. The masks a configuration writes for
    /// these vary — 172.16/12 is written `255.240.0.0` here — and a reader who
    /// has excluded 10/8 with an unusual mask has still excluded the local
    /// network, which is all this word claims.
    static let localRanges: Set<String> = [
        "10.0.0.0",         // RFC 1918
        "172.16.0.0",       // RFC 1918
        "192.168.0.0",      // RFC 1918
        "169.254.0.0",      // link-local
        "224.0.0.0",        // multicast
        "255.255.255.255",  // broadcast
    ]

    public static func summarize(_ routes: [Route]) -> Summary {
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
