import AppKit
import SwiftUI

/// Helm's mark, built from the very artwork the app icon is built from:
/// `helm-ring.svg` out of `Helm.icon`, drawn on the slab colour that variant
/// uses. macOS 26 resolves `.icon` variants at the system level — the app can
/// only ever read back the one matching the current appearance — so the mark
/// is composed here from the same source instead, which also lets it sit in
/// deliberate contrast to its window: the dark variant in light mode, the
/// light variant in dark mode.
///
/// Colours come from `icon.json`: the ring is black in the light variant and
/// white in the dark one, at 80% opacity, scaled 1.11; the light slab is a
/// near-white vertical gradient.
public struct HelmAppMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(size: CGFloat = 96) { self.size = size }

    /// Inverted on purpose: light window → dark mark, dark window → light mark.
    private var darkVariant: Bool { scheme == .light }

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
                .frame(width: size * 1.11, height: size * 1.11)
        } else {
            // Same geometry as the SVG (r=300, stroke 96 on a 1024 canvas).
            Circle()
                .strokeBorder(ringColor.opacity(0.8), lineWidth: size * 1.11 * (96.0 / 1024.0))
                .frame(width: size * 1.11 * (600.0 / 1024.0), height: size * 1.11 * (600.0 / 1024.0))
        }
    }

    private var ringColor: Color { darkVariant ? .white : .black }

    private var slabFill: LinearGradient {
        darkVariant
            ? LinearGradient(colors: [Color(white: 0.16), Color(white: 0.06)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 1.0), Color(white: 0.985)],
                             startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.7))
    }
}
