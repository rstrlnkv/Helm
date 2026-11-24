// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Module_VPN_Engine

/// Who raises this tunnel, capped to the four the door wears, so the card
/// says it without being opened.
enum VPNTenants {

    /// **Everything, and the part of it a door can wear.** The popover behind
    /// the door lists every rule, so the value carries the whole list and
    /// derives the cap.
    struct Strip: Equatable {
        /// Every application pointing at this tunnel, in the caller's order.
        let all: [String]
        /// The ones the door wears.
        var shown: [String] { Array(all.prefix(cap)) }
        /// How many more there are. Zero exactly when everything is on the
        /// door: «+0» is not drawn.
        var overflow: Int { max(all.count - cap, 0) }
        var total: Int { all.count }
    }

    /// **Four is a choice, not a width.** A card is drawn at
    /// `VPNGridLayout.cardCeiling` at every window Helm allows, and there six
    /// icons and the chip would still fit.
    static let cap = 4

    static func of(_ vpnName: String,
                   rules: [String: VPNAppRule],
                   sorted: ([String]) -> [String]) -> Strip {
        Strip(all: sorted(rules.filter { $0.value.vpnName == vpnName }.map(\.key)))
    }

    /// Where else a rule under this card could point, in the system's order.
    /// Empty on a Mac with one configuration, so the «Move» item is absent
    /// there.
    static func elsewhere(than vpnName: String, connections: [VPNConnection]) -> [String] {
        connections.map(\.name).filter { $0 != vpnName }
    }

    /// The rules pointing at a configuration this Mac does not have. They belong
    /// to no card's strip, and the page says so in one line under the grid.
    ///
    /// **An empty list of configurations orphans nothing.** `scutil` can answer
    /// with nothing on a refusal or a machine mid-boot, and that is a bad read,
    /// not every rule dead.
    static func orphaned(_ rules: [String: VPNAppRule],
                         connections: [String]) -> [String] {
        guard !connections.isEmpty else { return [] }
        let known = Set(connections)
        return rules.filter { !known.contains($0.value.vpnName) }.map(\.key)
    }
}
