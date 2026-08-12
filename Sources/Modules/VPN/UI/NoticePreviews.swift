// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI
import HelmUI
import Module_VPN_Engine

/// What each notice mode looks like, drawn rather than shipped as pictures so
/// the previews follow the appearance the way the rest of the app does.
///
/// A menu-bar corner with Helm's ring in it; what differs between the three is
/// exactly what the setting decides — nothing beside the ring, a name beside
/// it, or a banner below it.
///
/// **Every size is a fraction of the frame**, which is the same rule
/// `AppearanceThumbnail` follows and is what let these move from a 104×66 card
/// to the 74×46 one and back without a redraw. Written in points, they did not
/// move: the banner was 52 pt wide inside a 74 pt card, and the menu bar was a
/// third of its height.
///
/// **Redrawn 2026-08-12 from the Figma mockups**, which changed three things
/// and left the fourth alone:
///
/// - The desktop is `HelmWallpaper`, shared with the appearance thumbnail,
///   rather than a flat `Color.primary.opacity(0.06)`. The mockups draw one
///   desktop for both controls, measured to the pixel.
/// - **The menu bar has no strip behind it.** macOS 26 draws the bar as glass
///   over the wallpaper, so a grey band was the older system's shape; the
///   glyphs sit on the desktop now.
/// - There are the neighbours a real menu bar has — a signal-ish pair and the
///   clock — because a corner holding one glyph does not read as a menu bar at
///   all, which is the whole subject of this picture.
/// - `.system` still shows **no** name beside the ring, which is
///   `VPNNotice.showsMenuBarName`'s decision and the mockup's too: a banner
///   names the configuration in words, so the menu bar does not have to.
///
/// The clock is a shape, not digits. The mockups carry Apple's "9:41", and at
/// 104 pt real digits are three grey smudges — this stands for a clock the way
/// the two lines in the banner stand for a sentence.
enum NoticePreview {
    /// The picture for a mode, **derived from the mode** rather than described
    /// beside it.
    ///
    /// It was three hand-written pairs of booleans, and one of them was wrong:
    /// `.system` was drawn with a name in the menu bar while
    /// `VPNNotice.showsMenuBarName` is `self == .menuBar`, so the card for the
    /// loudest mode promised something the setting does not do. Nothing could
    /// have caught it — the enum and the picture agreed about nothing, because
    /// nothing connected them. They are one expression now, which is the same
    /// reason a command name is a constant both sides read rather than a
    /// literal typed twice (CLAUDE.md § A hand-written list…).
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
            // image unless a module tints it (`StatusItemController.refreshIcon`
            // → `tintToken`), so an accent ring here was drawing the uncommon
            // case — and drawing it invisibly: measured on this wallpaper it
            // came out at 1.4:1 in dark, a blue ring on blue. The banner's icon
            // below keeps the accent, where a notification really does carry
            // the app's own colour.
            Circle()
                .strokeBorder(Color.primary.opacity(0.75), lineWidth: 1.5)
                .frame(width: h * 0.121, height: h * 0.121)
            if name {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.70))
                    .frame(width: w * 0.160, height: h * 0.091)
            }
            // A signal-strength wedge and the clock. Both `secondary` rather
            // than `primary`: they are the room this picture stands in, and a
            // neighbour drawn as firmly as the subject makes the reader hunt
            // for which glyph the setting is about.
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
                        // The icon is round because notification icons are,
                        // and it is the app's own accent ring rather than a
                        // grey disc — the banner is Helm's, and this is the
                        // one place in the picture that says whose it is.
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
