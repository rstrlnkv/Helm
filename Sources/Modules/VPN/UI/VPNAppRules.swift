// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// The per-app automation half of the VPN settings page: the list of rules, what
/// each row says when it cannot fire, and the picker that writes one.
///
/// Its own file because the page reached the length limit, and this is where it
/// divides: everything above is about the connections this Mac has, and
/// everything here is about the rules a person wrote over them. The properties it
/// reads stay on the page — one `@State` of the rules, seeded and written back in
/// one place — so this is an extension rather than a view of its own.
extension VPNSettingsPage {

    /// Saves the rules and tells the engine to re-read them. `internal`, because
    /// the card's callbacks live on the page one file over.
    func persist() {
        VPNSettings(store: store).setRulesJSON(VPNRules.encode(rules))
        vm.send(VPNCommand.reloadRules)
    }

    /// **Where a rule's identity comes from, and the only place it can.** The path
    /// in front of a file dialog is somebody pointing at an app deliberately;
    /// everything downstream has only a bundle identifier, which is a string in a
    /// plist anybody can write. `VPNRules.adopting` decides what that does to the
    /// rules — including for an app that already has one, which is how a rule
    /// written before identities existed is repaired.
    ///
    /// **The tunnel is the caller's now.** It used to be
    /// `vm.connections.first?.name` — `scutil`'s creation order, which is not the
    /// order the page draws and never the tunnel that is up: on a Mac with two
    /// configurations, adding your first application was a coin flip nobody was
    /// told about. The button lives inside one card's popover, so the answer is
    /// that card.
    func pickApp(into vpnName: String) {
        let picked = AppPicker.chooseApps().map {
            (bundleID: $0.bundleID, identity: CodeIdentity.of(bundleAt: $0.url))
        }
        let updated = VPNRules.adopting(picked, into: rules, defaultVPN: vpnName)
        guard updated != rules else { return }
        rules = updated
        persist()
    }
}
