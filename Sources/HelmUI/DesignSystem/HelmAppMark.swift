import SwiftUI

/// Helm's mark, drawn rather than taken from the app icon.
///
/// macOS 26 resolves `.icon` asset variants at the system level: whatever the
/// current appearance is, `applicationIconImage` and the asset catalog both
/// hand back that one variant, and no drawing-appearance override changes it.
/// Since the mark is simple — a glass slab and a ring — drawing it directly is
/// the only way to control which variant appears, and it lets the mark sit in
/// deliberate contrast to the window it lives in: the dark slab in light mode,
/// the light slab in dark mode.
public struct HelmAppMark: View {
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme

    public init(size: CGFloat = 96) { self.size = size }

    /// Inverted on purpose: light window → dark mark, dark window → light mark.
    private var darkSlab: Bool { scheme == .light }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(slabFill)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                        .strokeBorder(darkSlab ? Color.white.opacity(0.10) : Color.black.opacity(0.06),
                                      lineWidth: max(size * 0.006, 0.5))
                )
                .shadow(color: .black.opacity(darkSlab ? 0.45 : 0.18),
                        radius: size * 0.06, x: 0, y: size * 0.03)
            Circle()
                .strokeBorder(ringFill, lineWidth: size * 0.125)
                .frame(width: size * 0.60, height: size * 0.60)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var slabFill: LinearGradient {
        darkSlab
            ? LinearGradient(colors: [Color(white: 0.17), Color(white: 0.07)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 1.0), Color(white: 0.93)],
                             startPoint: .top, endPoint: .bottom)
    }

    private var ringFill: LinearGradient {
        darkSlab
            ? LinearGradient(colors: [Color(white: 0.97), Color(white: 0.55)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: [Color(white: 0.18), Color(white: 0.55)],
                             startPoint: .top, endPoint: .bottom)
    }
}
