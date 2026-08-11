// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// What each notice mode looks like, drawn rather than shipped as pictures so
/// the previews follow the appearance the way the rest of the app does.
///
/// A menu-bar strip with Helm's ring in it; what differs between the three is
/// exactly what the setting decides — nothing beside the ring, a name beside
/// it, or a banner below it.
///
/// **Every size is a fraction of the frame**, which is the same rule
/// `AppearanceThumbnail` follows and is what let these move from a 104×66 card
/// to the 74×46 one every picture-choice in Helm is drawn at. Written in
/// points, they did not move: the banner was 52 pt wide inside a 74 pt card,
/// and the menu bar was a third of its height.
enum NoticePreview {
    static func strip(name: Bool, banner: Bool) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width, h = proxy.size.height
            ZStack(alignment: .top) {
                Rectangle().fill(Color.primary.opacity(0.06))
                VStack(spacing: 0) {
                    // The menu bar.
                    HStack(spacing: w * 0.029) {
                        Spacer()
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: 1.5)
                            .frame(width: h * 0.121, height: h * 0.121)
                        if name {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.70))
                                .frame(width: w * 0.327, height: h * 0.091)
                        }
                        Spacer().frame(width: w * 0.058)
                    }
                    .frame(height: h * 0.212)
                    .background(Color.primary.opacity(0.12))

                    if banner {
                        HStack(spacing: 4) {
                            Spacer()
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.22))
                                .frame(width: w * 0.5, height: h * 0.303)
                                .overlay(alignment: .leading) {
                                    VStack(alignment: .leading, spacing: h * 0.030) {
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(0.45))
                                            .frame(width: w * 0.25, height: h * 0.045)
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.primary.opacity(0.30))
                                            .frame(width: w * 0.173, height: h * 0.045)
                                    }
                                    .padding(.leading, w * 0.058)
                                }
                            Spacer().frame(width: w * 0.058)
                        }
                        .padding(.top, h * 0.076)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
