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
    /// The default route is the tunnel. The country is what the exit looked like
    /// from outside, when that could be read.
    case throughTunnel(country: String?)
    /// The tunnel is up and the machine is on the internet through something
    /// else. The state the check exists for.
    case besideTunnel
    /// One of the two routing readings was missing. Never dressed as either
    /// answer above.
    case unknown

    public static func of(tunnelInterface: String?, primaryInterface: String?,
                          country: String?) -> VPNExitVerdict {
        guard let tunnelInterface, let primaryInterface else { return .unknown }
        return tunnelInterface == primaryInterface
            ? .throughTunnel(country: country)
            : .besideTunnel
    }
}
