// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import HelmAppStrings

/// The three tabs of the Settings page — Basics, Log, About Helm — and the selection
/// they write.
///
/// Each tab is a `SettingsSelection` of its own, and each of the three pages
/// declares its own tabs and actions (`helmWindowToolbar`): Log declares its
/// own, and `SettingsDetail` declares General's and About's; what
/// they share is this list, so the switcher reads the same on all three.
enum SettingsTabs {
    /// In the order they are drawn; the ids are the ones `binding` understands.
    static var all: [HelmToolbarTab] {
        [HelmToolbarTab(id: "general", title: AppStr.settingsTabGeneral),
         HelmToolbarTab(id: "log", title: AppStr.logPane),
         HelmToolbarTab(id: "about", title: AppStr.aboutHelm)]
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
                if let tab = Self.selection(id) { selection.wrappedValue = tab }
            })
    }

    /// The selection a tab id stands for, nil for an id that is no tab.
    static func selection(_ id: String) -> SettingsSelection? {
        switch id {
        case "general": return .general
        case "log": return .log
        case "about": return .about
        default: return nil
        }
    }
}
