// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Where this Mac's traffic actually leaves from, as one of three answers.
///
/// **Routing decides, the country decorates.** Whether the default route is the
/// tunnel's own interface is a local reading that cannot fail silently; the
/// country comes from a server that can be slow, blocked or wrong. Folding them
/// into one boolean would let a failed request read as «no tunnel», which is a
/// warning about nothing, or as «through the tunnel», which is a reassurance
/// nobody checked.
public enum VPNExitVerdict: Codable, Equatable, Sendable {
    /// The default route is the tunnel, and this is the **two-letter region
    /// code** the exit answered — `NL`, not «Netherlands». It was spelled
    /// `country:` while holding a code, which is the kind of name a reader
    /// believes: the place is named in the app's own language by
    /// `VPNStr.country(_:)`, out of `Locale`, so no third party gets to write a
    /// country's name into Helm's window. Nil when the check could not be made
    /// or did not answer.
    case throughTunnel(countryCode: String?)
    /// The tunnel is up and the machine is on the internet through something
    /// else. The state the check exists for.
    case besideTunnel
    /// One of the two routing readings was missing. Never dressed as either
    /// answer above.
    case unknown

    /// Two sources for the routing half, asked in order.
    ///
    /// `primaryInterface` is `State:/Network/Global/IPv4` — the routing table's
    /// own answer, and the one that decides. `tunnelIsPrimary` is the
    /// `IsPrimaryInterface` line of the same `scutil --nc status` read that
    /// named the interface, which costs nothing extra and answers when the
    /// dynamic store could not be opened at all. A flag can be the connection's
    /// stale view of a route that has since moved, so it never overturns a store
    /// that answered; with neither the verdict stays `.unknown`, because a
    /// guess here is either a warning about nothing or a reassurance nobody
    /// checked.
    public static func of(tunnelInterface: String?, primaryInterface: String?,
                          tunnelIsPrimary: Bool?, countryCode: String?) -> VPNExitVerdict {
        guard let tunnelInterface else { return .unknown }
        if let primaryInterface {
            return tunnelInterface == primaryInterface
                ? .throughTunnel(countryCode: countryCode)
                : .besideTunnel
        }
        guard let tunnelIsPrimary else { return .unknown }
        return tunnelIsPrimary ? .throughTunnel(countryCode: countryCode) : .besideTunnel
    }
}
