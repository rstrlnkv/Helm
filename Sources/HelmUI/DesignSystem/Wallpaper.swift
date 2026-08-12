// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// The desktop behind a picture-choice preview: a blue-violet gradient, light
/// or dark, drawn at whatever size it is given.
///
/// **Shared because two previews draw the same desktop.** `AppearancePicker`'s
/// thumbnail and the VPN module's notice previews each had their own, and the
/// mockups they were drawn from use one wallpaper for both — measured off those
/// exports, the top-left pixel is `#AED4FD` in either of them. Two spellings of
/// one desktop is the variant `HelmChoiceCards` exists to prevent one layer up.
///
/// **The appearance is an argument, never the environment.** The automatic
/// appearance card draws *both* faces at once and masks one — so a wallpaper
/// that read `colorScheme` would paint the same half twice. The same reason a
/// render names its screen (ARCHITECTURE.md § A check that cannot fail is not
/// a check): inheriting an appearance is how a drawing stops being about what
/// it says it is about.
public struct HelmWallpaper: View {
    private let dark: Bool

    public init(dark: Bool) { self.dark = dark }

    /// Measured out of the mockups at the corners the gradient runs between.
    /// Light stays bright; **dark stays blue** rather than going nearly black,
    /// which is the one thing the previous drawing had differently — at
    /// `#12141F` the window floated in a void and the two cards read as "a
    /// window" and "a window at night" rather than as one desktop twice.
    private static let lightStops = [Color(red: 0.682, green: 0.831, blue: 0.992),   // #AED4FD
                                     Color(red: 0.565, green: 0.604, blue: 0.871)]   // #909ADE
    private static let darkStops = [Color(red: 0.424, green: 0.549, blue: 0.710),    // #6C8CB5
                                    Color(red: 0.337, green: 0.416, blue: 0.584)]     // #566A95

    public var body: some View {
        LinearGradient(colors: dark ? Self.darkStops : Self.lightStops,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
