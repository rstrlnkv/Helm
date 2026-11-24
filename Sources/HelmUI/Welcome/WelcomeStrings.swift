// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import Foundation

/// The tour's own words. Every module's name and summary comes from that
/// module's descriptor — a second copy here is one more set of descriptions
/// that go stale on the first rename.
///
/// The words are symbols of the kit's `Localizable.xcstrings`, same
/// as everywhere else in the app; Back, Next, Done and "open at login" are
/// `HelmWord`'s, the app's own established words, rather than a second,
/// slightly different translation of the same word.
public enum WelcomeStr {
    public static var windowTitle: String { L(.windowTitle) }
    static var introTitle: String { L(.introTitle) }
    /// The first sentence a newcomer reads, so it does not narrow the app to
    /// one of its surfaces: what is true of every surface is that Helm is made
    /// of modules, which is what the tour goes on to show.
    static var introBody: String { L(.introBody) }
    static var skip: String { L(.skip) }
    static var useThisModule: String { L(.useThisModule) }
    static var switchHint: String { L(.switchHint) }

    /// Read aloud in place of "3 of 10", which VoiceOver otherwise renders as
    /// two bare numbers with no idea what they count.
    static func stepPosition(_ step: Int, _ total: Int) -> String {
        L(.stepPosition(String(step), String(total)))
    }
}
