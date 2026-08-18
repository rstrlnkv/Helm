// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Which of the tunnels that are up the strip is about, and what order they are
/// offered in.
///
/// Both halves are here because they are one rule read from two ends: the list
/// is ordered with the default-route tunnel first, so «the first» names the
/// tunnel the traffic actually leaves through — and *therefore* falling back to
/// the first when a selection goes stale lands on the one honest default rather
/// than on whichever configuration was made earliest. Split across two files the
/// second half is a sentence with nothing keeping it.
///
/// Pure, so the page's fallback and the engine's ordering are each a value in
/// and a value out. The selection itself is `@State` on the page — a state of
/// this visit, never stored — and that is exactly why this has to answer for a
/// name that no longer names anything: the list is rewritten under it whenever
/// the network moves.
public enum VPNTunnelChoice {

    /// The tunnel the strip draws: the one the person picked while it is still
    /// up, and otherwise the first.
    ///
    /// Nil only for a Mac with nothing up, which is the page's own «no strip at
    /// all» — a selection that names nothing never answers nil, because two
    /// other tunnels are on the screen and an empty card is not one of them.
    public static func chosen(_ name: String?, among tunnels: [VPNTunnelState]) -> VPNTunnelState? {
        guard let name, let picked = tunnels.first(where: { $0.name == name })
        else { return tunnels.first }
        return picked
    }

    /// The tunnel carrying the default route first, the rest exactly as they
    /// came.
    ///
    /// The tail is **not** re-sorted, for the reason `VPNConnectionOrder` gives
    /// one file over: the tool's order is the person's own, and sorting by name
    /// would move every segment whenever a tunnel came up.
    ///
    /// With no routed tunnel — two tunnels up and the route on Wi-Fi, an
    /// ordinary Mac — nothing is promoted and the list is untouched.
    public static func primaryFirst(_ tunnels: [VPNTunnelState]) -> [VPNTunnelState] {
        tunnels.filter { $0.exit.carriesTheDefaultRoute }
            + tunnels.filter { !$0.exit.carriesTheDefaultRoute }
    }
}
