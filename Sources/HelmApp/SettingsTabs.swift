// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import HelmAppStrings

/// The three tabs of the Settings page — Basics, Log, About Helm — and the selection
/// they write.
///
/// Each tab is a `SettingsSelection` of its own, and each of the three pages
/// declares its own tabs and actions (`helmHeaderContent`): Log declares its
/// own, and `SettingsDetail` declares General's and About's; what
/// they share is this list, so the switcher reads the same on all three.
enum SettingsTabs {
    /// One row per tab, in the order they are drawn.
    private static var table: [(id: String, selection: SettingsSelection, title: String, symbol: String)] {
        [("general", .general, AppStr.settingsTabGeneral, "gearshape"),
         ("log", .log, AppStr.logPane, "text.alignleft"),
         ("about", .about, AppStr.aboutHelm, "info.circle")]
    }

    /// In the order they are drawn; the ids are the ones `binding` understands.
    static var all: [HelmHeaderTab] {
        table.map { HelmHeaderTab(id: $0.id, title: $0.title, symbol: $0.symbol) }
    }

    /// The tab a selection stands on: Log and About for themselves, and
    /// Basics for everything else — a module page is never shown with these
    /// tabs, so its answer only has to be harmless.
    static func binding(_ selection: Binding<SettingsSelection?>) -> Binding<String> {
        Binding(
            get: { table.first { $0.selection == selection.wrappedValue }?.id ?? "general" },
            set: { id in
                if let tab = Self.selection(id) { selection.wrappedValue = tab }
            })
    }

    /// The selection a tab id stands for, nil for an id that is no tab.
    static func selection(_ id: String) -> SettingsSelection? {
        table.first { $0.id == id }?.selection
    }
}
