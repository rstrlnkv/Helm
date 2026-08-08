// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

/// What each notice mode looks like, drawn rather than shipped as pictures so
/// the previews follow the appearance the way the rest of the app does.
///
/// A menu-bar strip with Helm's ring in it; what differs between the three is
/// exactly what the setting decides — nothing beside the ring, a name beside
/// it, or a banner below it.
enum NoticePreview {
    static func strip(name: Bool, banner: Bool) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06))
            VStack(spacing: 0) {
                // The menu bar.
                HStack(spacing: 3) {
                    Spacer()
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                        .frame(width: 8, height: 8)
                    if name {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.primary.opacity(0.70))
                            .frame(width: 34, height: 6)
                    }
                    Spacer().frame(width: 6)
                }
                .frame(height: 14)
                .background(Color.primary.opacity(0.12))

                if banner {
                    HStack(spacing: 4) {
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.primary.opacity(0.22))
                            .frame(width: 52, height: 20)
                            .overlay(alignment: .leading) {
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.primary.opacity(0.45))
                                        .frame(width: 26, height: 3)
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.primary.opacity(0.30))
                                        .frame(width: 18, height: 3)
                                }
                                .padding(.leading, 6)
                            }
                        Spacer().frame(width: 6)
                    }
                    .padding(.top, 5)
                }
                Spacer(minLength: 0)
            }
        }
    }
}
