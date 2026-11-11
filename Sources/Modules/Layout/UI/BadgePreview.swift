import AppKit
import HelmUI
import Module_Layout_Engine
import SwiftUI

/// Every installed layout, drawn exactly as the menu bar will draw it, so a style that shows letters
/// rather than a flag for one layout reads as the choice it is.
struct BadgePreview: View {
    let style: BadgeStyle
    let size: MenuBarIconSize
    /// The badges are AppKit bitmaps drawing with `labelColor`; nothing in a SwiftUI body sets the
    /// appearance those resolve against, so the scheme goes in by hand.
    @Environment(\.colorScheme) private var scheme

    private var sources: [InputSourceInfo] { InputSourceInfo.all() }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpace.s4) {
            Text(LyStr.badgePreview)
                .font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutLook.previewTile), spacing: HelmSpace.s5)],
                      alignment: .leading, spacing: HelmSpace.s4) {
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
                            .frame(width: LayoutLook.badgeSlot, alignment: .center)
                            .accessibilityHidden(true)
                        Text(source.name)
                            // The tick label under the picture; a step up truncates one language sooner.
                            .font(HelmText.pictureCaption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.vertical, HelmSpace.s1)
    }
}
