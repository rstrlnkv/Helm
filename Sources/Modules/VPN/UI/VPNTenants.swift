// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Module_VPN_Engine

/// Who raises this tunnel — the card's own answer, capped to what a card can
/// hold.
///
/// The flat list of rules said what each rule was asked to do and never said
/// this; a strip of application icons on the card says it without being opened,
/// which is the whole point of putting the rules behind a door.
enum VPNTenants {

    /// **Everything, and the part of it a door can wear.** The strip on the closed
    /// card is capped by width; the popover behind it has room for the lot, and a
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

    /// **Four, and the number is a width rather than a taste.** The settings
    /// column clamps to the pane, so at the minimum window a card is about
    /// 297 pt with 273 of content, and there the strip's own chrome — 8 pt of
    /// padding a side, 6 between icons, 6 before its chevron and 9 for the
    /// chevron — plus four 22 pt icons, plus the overflow chip, plus the notices
    /// door beside it, comes to 214. Five icons fit there and not in the 190 pt
    /// card the grid still declares as its floor.
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
