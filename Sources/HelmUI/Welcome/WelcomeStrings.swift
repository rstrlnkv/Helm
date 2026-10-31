// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The tour's own words. Every module's name and summary comes from that
/// module's descriptor — a second copy here is one more set of descriptions
/// that go stale on the first rename.
///
/// The words are symbols of the kit's `Localizable.xcstrings`, same
/// as everywhere else in the app; `back` and `done` share the app's own
/// established "Back" and "Done" rather than carrying a second, slightly
/// different translation of the same word.
public enum WelcomeStr {
    public static var windowTitle: String { L(.windowTitle) }
    public static var introTitle: String { L(.introTitle) }
    /// The first sentence a newcomer reads, so it does not narrow the app to
    /// one of its surfaces: «lives in the menu bar» was written when that was
    /// the whole app, and by the time anyone read it there were also a panel,
    /// a settings window and a sidebar. What is true of every surface is that
    /// Helm is made of modules, which is also what the tour goes on to show.
    public static var introBody: String {
        L(.introBody)
    }
    public static var back: String { L(.back) }
    public static var next: String { L(.next) }
    public static var skip: String { L(.skip) }
    public static var done: String { L(.done) }
    public static var useThisModule: String { L(.useThisModule) }
    public static var switchHint: String { L(.switchHint) }
    /// Shares the app's own key rather than a second table entry for the same
    /// English — the intro is the one place outside Settings this is asked.
    public static var launchAtLogin: String { L(.openHelmAtLogin) }

    /// Read aloud in place of "3 of 10", which VoiceOver otherwise renders as
    /// two bare numbers with no idea what they count.
    public static func stepPosition(_ step: Int, _ total: Int) -> String {
        L(.stepPosition(String(step), String(total)))
    }
}
