// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// Everything the tour can do outside itself.
///
/// One value rather than five arguments carried through two initialisers. The
/// window's `show` was already at six and warned about; a fifth closure would
/// have made it seven, and every one of them is the same kind of thing — a
/// question the tour cannot answer and a change it cannot make.
///
/// Every field has a default, so a preview or a test names only the one it is
/// about. The defaults are the harmless answers: every module on, no login
/// item, and a button that goes nowhere.
public struct WelcomeActions {
    public var isModuleEnabled: (String) -> Bool
    public var setModuleEnabled: (String, Bool) -> Void
    public var isLaunchAtLogin: () -> Bool
    /// Answers with what the login item **is** afterwards, not with what it was
    /// asked to be: registration can be refused, and a tour switch that stays
    /// where the finger left it is the same lie the settings page had.
    public var setLaunchAtLogin: (Bool) -> Bool
    /// Take somebody to that module's page, which is where whatever it offered
    /// to set up actually is.
    public var openModule: (String) -> Void

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
