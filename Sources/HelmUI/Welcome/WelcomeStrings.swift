// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The tour's own words. Every module's name and summary comes from that
/// module's descriptor — a second copy here is nine descriptions that go stale
/// on the first rename.
///
/// English is the key into `Resources/<lang>.lproj/Localizable.strings`, same
/// as everywhere else in the app; `back` and `done` share the app's own
/// established "Back" and "Done" rather than carrying a second, slightly
/// different translation of the same word.
public enum WelcomeStr {
    public static var windowTitle: String { L("Welcome to Helm") }
    public static var introTitle: String { L("Tools for your Mac") }
    /// The first sentence a newcomer reads, so it does not narrow the app to
    /// one of its surfaces: «lives in the menu bar» was written when that was
    /// the whole app, and by the time anyone read it there were also a panel,
    /// a settings window and a sidebar. What is true of every surface is that
    /// Helm is made of modules, which is also what the tour goes on to show.
    public static var introBody: String {
        L("Helm is made of modules. Each one does a single job, and you can switch off the ones you do not want.")
    }
    public static var back: String { L("Back") }
    public static var next: String { L("Next") }
    public static var skip: String { L("Skip") }
    public static var done: String { L("Done") }
    public static var useThisModule: String { L("Use this module") }
    public static var switchHint: String { L("You can change this later in Settings.") }
    /// Shares the app's own key rather than a second table entry for the same
    /// English — the intro is the one place outside Settings this is asked.
    public static var launchAtLogin: String { L("Open Helm at login") }

    /// Read aloud in place of "3 of 10", which VoiceOver otherwise renders as
    /// two bare numbers with no idea what they count.
    public static func stepPosition(_ step: Int, _ total: Int) -> String {
        L("Step \(step) of \(total)", [.ru: "Шаг \(step) из \(total)", .es: "Paso \(step) de \(total)", .fr: "Étape \(step) sur \(total)", .de: "Schritt \(step) von \(total)", .ja: "\(total) 中 \(step) ステップ目", .zh: "第 \(step) 步，共 \(total) 步", .pt: "Passo \(step) de \(total)"])
    }
}
