import AppKit
import HelmUI
import Module_Layout_Engine
import SwiftUI

/// Every installed layout, drawn exactly as the menu bar will draw it.
///
/// The style picker used to be four lines of text, so the first place a user
/// found out that their US layout shows letters rather than a flag was the
/// menu bar — where it reads as the setting having failed. Shown here beside
/// the flags it does have, the same fact reads as what it is: a choice, and
/// the one macOS itself makes for that layout.
struct BadgePreview: View {
    let style: BadgeStyle
    let size: MenuBarIconSize
    /// The badges are AppKit bitmaps drawing with `labelColor`; inside a
    /// SwiftUI body nothing sets the appearance those resolve against, so in a
    /// light window the letters came out white on white.
    @Environment(\.colorScheme) private var scheme

    private var sources: [InputSourceInfo] { InputSourceInfo.all() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LyStr.badgePreview)
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 10)],
                      alignment: .leading, spacing: 8) {
                ForEach(sources, id: \.id) { source in
                    HStack(spacing: 7) {
                        // The real image, not an impression of it: the whole
                        // point is that this cannot disagree with the menu bar.
                        Image(nsImage: HelmAppearance.rasterize(
                            BadgeImage.make(label: source.badge,
                                            flag: source.emojiFlag,
                                            art: source.art,
                                            style: style,
                                            points: size.points),
                            scheme: scheme))
                            .frame(width: 26, alignment: .center)
                            .accessibilityHidden(true)
                        Text(source.name)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
