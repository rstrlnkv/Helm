// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Module_VPN_Engine

/// Who raises this tunnel — the card's own answer, capped to the four the door
/// wears.
///
/// A strip of application icons on the card says it without being opened, which
/// is the whole point of putting the rules behind a door.
enum VPNTenants {

    /// **Everything, and the part of it a door can wear.** The strip on the closed
    /// card is capped; the popover behind it has room for the lot, and a
    /// popover that listed four of eleven rules with «and 7 more» would be a door
    /// that cannot be opened all the way. So the value carries the whole list and
    /// derives the cap, rather than being handed the cap and losing the rest.
    struct Strip: Equatable {
        /// Every application pointing at this tunnel, in the caller's order.
        let all: [String]
        /// The ones the door wears.
        var shown: [String] { Array(all.prefix(cap)) }
        /// How many more there are. Zero exactly when everything is on the door —
        /// «+0» is not a thing to draw.
        var overflow: Int { max(all.count - cap, 0) }
        var total: Int { all.count }
    }

    /// **Four is a choice, not a width.** A card is drawn at
    /// `VPNGridLayout.cardCeiling`, 346 pt with 322 of content, at every window
    /// Helm allows (`cardMinimum`'s 190 is never reached), and there the door
    /// row with four icons, the overflow chip and the notices door comes to 256;
    /// six icons and the chip would fit in 312, a seventh would not.
    static let cap = 4

    static func of(_ vpnName: String,
                   rules: [String: VPNAppRule],
                   sorted: ([String]) -> [String]) -> Strip {
        Strip(all: sorted(rules.filter { $0.value.vpnName == vpnName }.map(\.key)))
    }

    /// Where else a rule under this card could point: the system's own order,
    /// minus the tunnel it is already under. It is what the row's «Move» menu
    /// offers, and it is empty on a Mac with one configuration — which is why
    /// that menu item is absent there rather than present and useless.
    static func elsewhere(than vpnName: String, connections: [VPNConnection]) -> [String] {
        connections.map(\.name).filter { $0 != vpnName }
    }

    /// The rules pointing at a configuration this Mac does not have. They belong
    /// to no card's strip, and the page says so in one line under the grid.
    ///
    /// **An empty list of configurations orphans nothing.** `scutil` can answer
    /// with nothing at all — a refusal, a machine mid-boot — and a page that
    /// then announced every rule as dead would be shouting about a bad read.
    /// The same rule the rest of this module follows about empty answers.
    static func orphaned(_ rules: [String: VPNAppRule],
                         connections: [String]) -> [String] {
        guard !connections.isEmpty else { return [] }
        let known = Set(connections)
        return rules.filter { !known.contains($0.value.vpnName) }.map(\.key)
    }
}
