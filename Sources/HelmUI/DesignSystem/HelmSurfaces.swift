import AppKit
import SwiftUI

extension View {
    /// The edge of a **preview picture** — a drawn thumbnail of what a setting
    /// does: clipped to the control corner, with a hairline all round.
    ///
    /// The hairline is not decoration: a preview whose own fill matches the
    /// surface behind it floats in nothing. A chosen one wears the accent
    /// instead, thicker, which is the only difference between a row of them to
    /// choose from (`HelmChoiceCards`) and a single one beside the control that
    /// sets it (VPN's notices popover).
    public func helmPreviewEdge(chosen: Bool = false) -> some View {
        clipShape(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .strokeBorder(chosen ? Color.accentColor : HelmSurface.hairline,
                                  lineWidth: chosen ? 2.5 : 0.5)
            }
    }

    /// The one card in Helm: soft fill, continuous corners, no border.
    ///
    /// No border on purpose: grouped-`Form` sections are drawn by the system as
    /// a plain fill and cannot be restyled, so an outlined card of our own would
    /// read as a different kind of box on the next page
    /// (Architecture/DesignSystem.md § Surfaces).
    public func helmCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(HelmSurface.cardFill)
            )
    }
}

/// The icon plate, used wherever a screen introduces itself: the symbol on its
/// tint, lit the way macOS 26 lights an app icon, with a soft shadow *under* it
/// rather than a halo around it.
///
/// A halo has nowhere to go: the header below the plate cuts it flat along the
/// bottom, and a radial gradient shows a rim where its ramp ends. A shadow is a
/// Gaussian blur, with no rim, small enough to sit inside the header's padding.
///
/// The same drawing is the small tile in the panel and the order list. The
/// settings sidebar draws `ShellGlyphView`, not this.
public struct HelmIconPlate: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44
    /// A panel tile for a module that is switched off: the shape stays so the
    /// row does not move, the colour goes so it does not claim to be running.
    var active: Bool = true

    public init(symbol: String, tint: Color, size: CGFloat = 44, active: Bool = true) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
        self.active = active
    }

    /// A glyph keeps a constant *proportion* of a large plate, but at row size
    /// that proportion stops being legible, so the smaller tiles give the
    /// symbol more of the square.
    ///
    /// The ratios are read off real renders against System Settings' sidebar
    /// tile, whose symbol fills 0.70 of it, not computed: SwiftUI sizes a symbol
    /// against the font's metrics, so the ink is about 1.34× the point size.
    private var glyphSize: CGFloat {
        let base: CGFloat = switch size {
        case ...32: size * 0.47
        default: size * 0.44
        }
        // Corrected per symbol: one point size across the set varies 28% in
        // visual size. `SymbolInk` has the measurements.
        return base * SymbolInk.correction(for: symbol)
    }

    /// The shadow's ratios reproduce the profile of System Settings' sidebar
    /// tile: a vertical gradient, and a neutral shadow, not a tinted one, deeper
    /// and longer underneath, which is a small downward offset.
    private var shadowRadius: CGFloat { size * 0.09 }
    private var shadowOffset: CGFloat { size * 0.045 }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(HelmText.onFill)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(active ? AnyShapeStyle(tint.gradient)
                                 : AnyShapeStyle(Color.secondary.opacity(0.45)))
            )
            // Neutral, not tinted: the system's is grey at every hue, and a
            // tinted one reads as a glow again at the sizes where it shows.
            // Dropped when the tile is off, since an unlit thing casts nothing.
            .shadow(color: .black.opacity(active ? 0.16 : 0),
                    radius: shadowRadius, y: shadowOffset)
            // Decoration at every call site: a title always sits beside it, and
            // a visible symbol would announce its raw name before the heading.
            .accessibilityHidden(true)
    }
}

/// A plate that carries a *verdict's* signal rather than a module's identity —
/// the orange warning or green check a page answers with.
///
/// It draws exactly what `HelmIconPlate` draws; it has its own name so that the
/// two meanings stay apart, and so that its tint is a signal from `HelmSignal`
/// or grey, never a module's colour.
public struct HelmSignalPlate: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 44

    public init(symbol: String, tint: Color, size: CGFloat = 44) {
        self.symbol = symbol
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        HelmIconPlate(symbol: symbol, tint: tint, size: size)
    }
}

/// The heading over a group of rows: small, quiet, sentence case.
///
/// The system's `Section("…")` draws 13 pt semibold, the weight of the rows
/// under it and two points below the page's name. This is a label rather than
/// a title, 11 pt semibold in the quiet ink, so the eye reads the group as a
/// group and the page keeps one title.
public struct HelmSectionTitle: View {
    private let title: String
    public init(_ title: String) { self.title = title }

    public var body: some View {
        // Not uppercased: capitals are a second voice, kept for the badge and
        // the metric strip's labels, where a word is a token. A section heading
        // names the thing below it in the voice the rows are written in.
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(HelmText.quiet)
            // A heading over rows is a heading to the rotor, said once here so a
            // call site cannot forget it. The trait is a set, so saying it again
            // changes nothing.
            .accessibilityAddTraits(.isHeader)
    }
}

/// Instrument readout: monospaced figures over small-caps labels, split by
/// hairlines — the About page's version/build/modules row, generalized.
public struct HelmMetricStrip: View {
    /// Keeps a tint readable on a light background without inventing a palette:
    /// the system colours are chosen for dark, and the light theme is where
    /// they fail.
    @Environment(\.helmTraits) private var traits

    /// Static so the fraction can be measured: a blend depth is a contrast
    /// decision. At 0.40 the green, orange and teal figures clear 4.5:1 against
    /// the window in light, at 16 pt medium.
    ///
    /// The tint is resolved in the light appearance explicitly rather than in
    /// whatever `NSAppearance.current` holds: `NSColor(Color)` asks the ambient
    /// appearance, while this runs under `colorScheme == .light` taken from the
    /// environment, and with the two disagreeing the blend darkens Dark's
    /// brighter green and calls it a Light colour.
    static func legible(_ tint: Color, in scheme: ColorScheme) -> Color {
        guard scheme == .light else { return tint }
        var darkened = NSColor(tint)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            // Both steps inside the block, and sRGB before the blend:
            // `NSColor(Color)` is dynamic, so blending outside would resolve it
            // again against whatever appearance is current then.
            let base = NSColor(tint).usingColorSpace(.sRGB) ?? NSColor(tint)
            darkened = base.blended(withFraction: 0.40, of: .black) ?? base
        }
        return Color(nsColor: darkened)
    }

    public struct Metric: Identifiable {
        /// The label, not a fresh UUID: metrics are rebuilt inline from view
        /// model state, and a new identity per publish makes `ForEach` re-create
        /// every cell instead of updating it.
        public var id: String { label }
        let value: String
        public let label: String
        let tint: Color?

        public init(_ value: String, _ label: String, tint: Color? = nil) {
            self.value = value
            self.label = label
            self.tint = tint
        }
    }

    let metrics: [Metric]

    public init(_ metrics: [Metric]) { self.metrics = metrics }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(metrics.enumerated()), id: \.element.id) { index, metric in
                if index > 0 {
                    Rectangle()
                        .fill(HelmSurface.hairline)
                        .frame(width: 1, height: 26)
                }
                VStack(spacing: HelmSpace.s1) {
                    Text(metric.value)
                        .helmMetricFigure()
                        // Figures roll rather than cut; Keep Awake's is a
                        // countdown at 1 Hz.
                        .contentTransition(.numericText())
                        .animation(HelmMotion.interface, value: metric.value)
                        // A system tint is built for a dark background, so it is
                        // darkened in light for the figure to read in both (`legible`).
                        .foregroundStyle(metric.tint.map { Self.legible($0, in: traits.scheme) } ?? .primary)
                    Text(metric.label)
                        // 10, the scale's bottom step.
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // The token: `.tertiary` here falls below every threshold.
                        .foregroundStyle(HelmText.quiet)
                }
                // "Running, State" as one VoiceOver stop, not two in
                // value-then-label order.
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
