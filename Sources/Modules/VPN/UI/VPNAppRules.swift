// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmRuntime
import HelmUI
import Module_VPN_Engine

/// The per-app automation half of the VPN settings page: saving the rules and
/// the picker that writes one.
///
/// Its own file for length. The properties it reads stay on the page, one
/// `@State` of the rules seeded and written back in one place, so this is an
/// extension rather than a view of its own.
extension VPNSettingsPage {

    /// Saves the rules through the model, which tells the engine to re-read them. `internal`, because
    /// the card's callbacks live on the page one file over.
    func persist() {
        vm.saveRules(rules)
    }

    /// **Where a rule's identity comes from, and the only place it can.** A
    /// path picked in a file dialog is somebody pointing at an app
    /// deliberately; downstream there is only a bundle identifier, which any
    /// plist can claim. `VPNRules.adopting` decides what that does to the
    /// rules, including repairing a rule with no identity.
    ///
    /// **The tunnel is the caller's.** `scutil`'s creation order is neither the
    /// page's order nor the tunnel that is up, so a default would be a coin
    /// flip. The button lives in one card's popover, so the answer is that card.
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
