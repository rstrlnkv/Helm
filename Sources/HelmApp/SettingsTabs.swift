// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI

/// The three tabs of the Settings page — Basics, Log, About Helm — and the selection
/// they write.
///
/// Each tab is a `SettingsSelection` of its own, and each of the three pages
/// has a bar under its own key (`SettingsToolbar`'s `pageKey`): Log declares its
/// own, and `SettingsDetail` declares General's and About's; what
/// they share is this list, so the switcher reads the same on all three.
enum SettingsTabs {
    /// In the order they are drawn; the ids are the ones `binding` understands.
    static var all: [HelmToolbarTab] {
        [HelmToolbarTab(id: "general", title: AppStr.settingsTabGeneral, symbol: "gearshape"),
         HelmToolbarTab(id: "log", title: AppStr.logPane, symbol: "text.alignleft"),
         HelmToolbarTab(id: "about", title: AppStr.aboutHelm, symbol: "info.circle")]
    }

    /// The tab a selection stands on: Log and About for themselves, and
    /// Basics for everything else — a module page is never shown with these
    /// tabs, so its answer only has to be harmless.
    static func binding(_ selection: Binding<SettingsSelection?>) -> Binding<String> {
        Binding(
            get: {
                switch selection.wrappedValue {
                case .log: return "log"
                case .about: return "about"
                default: return "general"
                }
            },
            set: { id in
                switch id {
                case "general": selection.wrappedValue = .general
                case "log": selection.wrappedValue = .log
                case "about": selection.wrappedValue = .about
                default: break
                }
            })
    }
}
