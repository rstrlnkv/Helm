// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// What each notice mode looks like, drawn rather than shipped as pictures so
/// the previews follow the appearance the way the rest of the app does.
///
/// A menu-bar corner with Helm's ring in it; the three differ in exactly what
/// the setting decides: nothing beside the ring, a name beside it, or a banner
/// below it.
///
/// **Every size is a fraction of the frame**, as in `AppearanceThumbnail`, so
/// these draw at any card size.
///
/// - The desktop is `HelmWallpaper`, shared with the appearance thumbnail.
/// - **The menu bar has no strip behind it**: macOS 26 draws the bar as glass
///   over the wallpaper.
/// - A signal-ish pair and the clock stand beside the ring, because a corner
///   holding one glyph does not read as a menu bar.
/// - `.system` shows **no** name beside the ring
///   (`VPNNotice.showsMenuBarName`): the banner names the configuration.
///
/// The clock is a shape, not digits: at 104 pt real digits are grey smudges.
/// `@MainActor` because each of these builds a view for `VPNConnectionCard`.
@MainActor
enum NoticePreview {
    /// The picture for a mode, **derived from the mode** rather than described
    /// beside it, so the picture cannot promise what the setting does not do.
    static func of(_ mode: VPNNotice) -> some View {
        strip(name: mode.showsMenuBarName, banner: mode.postsBanner)
    }

    static func strip(name: Bool, banner: Bool) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            // The appearance is the environment's here, unlike the appearance
            // picker: this preview draws one desktop, not both at once.
            EnvironmentReader { scheme in
                ZStack(alignment: .top) {
                    HelmWallpaper(dark: scheme == .dark)

                    VStack(spacing: 0) {
                        menuBar(w: w, h: h, name: name)
                        if banner { self.banner(w: w, h: h) }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    /// The top-right corner of a menu bar: Helm's ring, the name when the
    /// setting asks for it, then the neighbours that make it a menu bar.
    private static func menuBar(w: CGFloat, h: CGFloat, name: Bool) -> some View {
        HStack(spacing: w * 0.029) {
            Spacer()
            // **Monochrome, not the accent.** The status item is a template
            // image unless a module tints it (`StatusItemController.refreshIcon`),
            // and an accent ring on this wallpaper is a blue ring on blue in
            // dark. The banner's icon keeps the accent, as a notification does.
            Circle()
                .strokeBorder(Color.primary.opacity(0.75), lineWidth: 1.5)
                .frame(width: h * 0.121, height: h * 0.121)
            if name {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.70))
                    .frame(width: w * 0.160, height: h * 0.091)
            }
            // A signal-strength wedge and the clock, fainter than the ring so
            // the reader sees which glyph the setting is about.
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.45))
                .frame(width: w * 0.048, height: h * 0.091)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.primary.opacity(0.45))
                .frame(width: w * 0.087, height: h * 0.091)
            Spacer().frame(width: w * 0.058)
        }
        .frame(height: h * 0.212)
    }

    /// The notification: a round app icon and two lines of what it says.
    private static func banner(w: CGFloat, h: CGFloat) -> some View {
        HStack(spacing: 4) {
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.22))
                .frame(width: w * 0.5, height: h * 0.303)
                .overlay(alignment: .leading) {
                    HStack(spacing: w * 0.029) {
                        // Round, as notification icons are, with the app's
                        // accent ring: the one mark saying whose banner it is.
                        Circle()
                            .fill(Color.primary.opacity(0.10))
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 1))
                            .frame(width: h * 0.136, height: h * 0.136)
                        VStack(alignment: .leading, spacing: h * 0.030) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.primary.opacity(0.45))
                                .frame(width: w * 0.135, height: h * 0.045)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.primary.opacity(0.30))
                                .frame(width: w * 0.221, height: h * 0.045)
                        }
                    }
                    .padding(.leading, w * 0.029)
                }
            Spacer().frame(width: w * 0.058)
        }
        .padding(.top, h * 0.076)
    }
}

/// Reads the colour scheme and hands it to a closure — a `View` because the
/// wallpaper needs the appearance as a value and `@Environment` is only
/// available inside one.
private struct EnvironmentReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: (ColorScheme) -> Content
    init(@ViewBuilder _ content: @escaping (ColorScheme) -> Content) { self.content = content }
    var body: some View { content(scheme) }
}
