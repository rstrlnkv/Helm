import AppKit
import SwiftUI

/// Helm's mark, built from the very artwork the app icon is built from:
/// `helm-ring.svg` out of `Helm.icon`, drawn on a slab that copies the system
/// fill that variant uses. macOS 26 resolves `.icon` variants at the system
/// level — the app can only ever read back the one matching the current
/// appearance — so the mark is composed here from the same source instead,
/// which also lets it sit in deliberate contrast to its window: the dark
/// variant in light mode, the light variant in dark mode.
///
/// The ring follows `icon.json`: the artwork, the layer scale 3.05, the colour
/// (black in the light variant, white in the dark and tinted ones) carrying
/// the alpha 0.8, the layer opacity 1. `icon.json` names only the slab's fill,
/// not its colours; the slab copies the system fills `system-light` and
/// `system-dark` as compiled into `Assets.car` (`xcrun assetutil --info`): a
/// top-to-bottom gradient over the full height, gray gamma 2.2, 1.0 to 0.925
/// and 0.192 to 0.078. Both are copied here by hand, as `Color(white:)`: on
/// screen it matches the "gray gamma 22" of `Assets.car`, while
/// `NSColor(calibratedWhite:)` did not (it rendered 0.192 as 62 instead of 48).
public struct HelmAppMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(size: CGFloat = 96) { self.size = size }

    /// Inverted on purpose: light window → dark mark, dark window → light mark.
    private var darkVariant: Bool { scheme == .light }

    /// The SVG is a 256 pt canvas the ring fills edge to edge; the layer is
    /// scaled 3.05 on Icon Composer's 1024 pt canvas, so the ring spans
    /// 256 * 3.05 / 1024 of the slab.
    private static let ringScale: CGFloat = 256 * 3.05 / 1024

    private static let ring: NSImage? = {
        guard let url = Bundle.main.url(forResource: "helm-ring", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(slabFill)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(darkVariant ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                                      lineWidth: max(size * 0.006, 0.5))
                )
                .shadow(color: .black.opacity(darkVariant ? 0.45 : 0.18),
                        radius: size * 0.06, x: 0, y: size * 0.03)
            ringView
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var ringView: some View {
        if let ring = Self.ring {
            Image(nsImage: ring)
                .resizable()
                .renderingMode(.template)
                .foregroundStyle(ringColor)
                .opacity(0.8)
                .frame(width: size * Self.ringScale, height: size * Self.ringScale)
        } else {
            // Same geometry as the SVG (outer r 128, inner r 90 on a 256 canvas).
            Circle()
                .strokeBorder(ringColor.opacity(0.8), lineWidth: size * Self.ringScale * (38.0 / 256.0))
                .frame(width: size * Self.ringScale, height: size * Self.ringScale)
        }
    }

    private var ringColor: Color { darkVariant ? .white : .black }

    private var slabFill: LinearGradient {
        LinearGradient(colors: darkVariant ? [Color(white: 0.192), Color(white: 0.078)]
                                           : [Color(white: 1.0), Color(white: 0.925)],
                       startPoint: .top, endPoint: .bottom)
    }
}
