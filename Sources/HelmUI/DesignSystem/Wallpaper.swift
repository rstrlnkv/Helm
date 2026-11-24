// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// The desktop behind a picture-choice preview: a blue-violet gradient, light
/// or dark, drawn at whatever size it is given.
///
/// Shared, because `AppearancePicker`'s thumbnail and VPN's notice previews
/// show the same desktop, as in the mockups they are drawn from.
///
/// **The appearance is an argument, never the environment.** The automatic
/// appearance card draws *both* faces at once and masks one — so a wallpaper
/// that read `colorScheme` would paint the same half twice. The same reason a
/// render names its screen: inheriting an appearance is how a drawing stops
/// being about what it says it is about.
public struct HelmWallpaper: View {
    private let dark: Bool

    public init(dark: Bool) { self.dark = dark }

    /// Measured out of the mockups at the corners the gradient runs between.
    /// Light stays bright; dark stays blue rather than nearly black, so the two
    /// cards read as one desktop twice, not a window in a void.
    private static let lightStops = [Color(red: 0.682, green: 0.831, blue: 0.992),   // #AED4FD
                                     Color(red: 0.565, green: 0.604, blue: 0.871)]   // #909ADE
    private static let darkStops = [Color(red: 0.424, green: 0.549, blue: 0.710),    // #6C8CB5
                                    Color(red: 0.337, green: 0.416, blue: 0.584)]     // #566A95

    public var body: some View {
        LinearGradient(colors: dark ? Self.darkStops : Self.lightStops,
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
