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
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: HelmSpace.s5)],
                      alignment: .leading, spacing: 8) {
                ForEach(sources, id: \.id) { source in
                    HStack(spacing: HelmSpace.s3) {
                        // The real image, not an impression of it: the whole
                        // point is that this cannot disagree with the menu bar.
                        Image(nsImage: HelmAppearance.rasterize(
                            BadgeImage.make(label: source.badge,
                                            region: source.region,
                                            style: style,
                                            points: size.points),
                            scheme: scheme))
                            .frame(width: 26, alignment: .center)
                            .accessibilityHidden(true)
                        Text(source.name)
                            // **10 is meant here.** A caption under a picture,
                            // like the choice cards': the badge is the subject
                            // of this tile and the name is the tick label under
                            // it. The tile is 132 pt of which 26 is the badge,
                            // and this row already truncates — a step up buys
                            // nothing and truncates one language sooner.
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
