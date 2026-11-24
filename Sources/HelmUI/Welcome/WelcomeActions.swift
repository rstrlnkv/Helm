// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Everything the tour can do outside itself.
///
/// One value rather than a closure per question: each is a question the tour
/// cannot answer or a change it cannot make, and the window's `show` would
/// otherwise carry them all.
///
/// Every field has a default, so a preview or a test names only the one it is
/// about. The defaults are the harmless answers: every module on, no login
/// item, and a button that goes nowhere.
public struct WelcomeActions {
    var isModuleEnabled: (String) -> Bool
    var setModuleEnabled: (String, Bool) -> Void
    var isLaunchAtLogin: () -> Bool
    /// Answers with what the login item **is** afterwards, not what it was
    /// asked to be: registration can be refused, and a switch that stays where
    /// the finger left it would be lying.
    var setLaunchAtLogin: (Bool) -> Bool
    /// Take somebody to that module's page, which is where whatever it offered
    /// to set up actually is.
    var openModule: (String) -> Void

    public init(isModuleEnabled: @escaping (String) -> Bool = { _ in true },
                setModuleEnabled: @escaping (String, Bool) -> Void = { _, _ in },
                isLaunchAtLogin: @escaping () -> Bool = { false },
                setLaunchAtLogin: @escaping (Bool) -> Bool = { $0 },
                openModule: @escaping (String) -> Void = { _ in }) {
        self.isModuleEnabled = isModuleEnabled
        self.setModuleEnabled = setModuleEnabled
        self.isLaunchAtLogin = isLaunchAtLogin
        self.setLaunchAtLogin = setLaunchAtLogin
        self.openModule = openModule
    }
}
