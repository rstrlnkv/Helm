import AppKit
import SwiftUI

public extension View {
    /// The edge of a **preview picture** — a drawn thumbnail of what a setting
    /// does: clipped to the control corner, with a hairline all round.
    ///
    /// The hairline is not decoration. A preview whose own fill matches the
    /// surface behind it floats in nothing — measured at 1.00:1 for the light
    /// thumbnail in light appearance and 1.12:1 dark on dark. A chosen one wears
    /// the accent instead, thicker, which is the only thing that ever differs
    /// between the two places these are drawn: a row of them to choose from
    /// (`HelmChoiceCards`) and a single one beside the control that sets it
    /// (VPN's notices popover).
    func helmPreviewEdge(chosen: Bool = false) -> some View {
        clipShape(RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .strokeBorder(chosen ? Color.accentColor : HelmSurface.hairline,
                                  lineWidth: chosen ? 2.5 : 0.5)
            }
    }

    /// The one card in Helm: soft fill, continuous corners, no border.
    ///
    /// No border on purpose. Half of Helm's containers are macOS grouped-Form
    /// sections, which the system draws as a plain fill and which we cannot
    /// restyle — so an outlined card of our own would read as a different kind
    /// of box on the next page over. The system's treatment is the anchor.
    func helmCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.card, style: .continuous)
                    .fill(HelmSurface.cardFill)
            )
    }
}

/// The icon plate from the About page, reused wherever a screen introduces
/// itself: the symbol on its tint, lit the way macOS 26 and iOS 26 light an
/// app icon — a soft shadow *under* it, not a halo around it.
///
/// It was a halo: a `RadialGradient` of the tint, drawn in a frame twice the
/// plate's size. Two things were wrong with it, and both were visible.
///
/// It ended in a straight line. The glow is 44 pt of bloom hanging off a 44 pt
/// plate, and the header that holds it is 18 pt of padding and then a divider —
/// so the light spread up and sideways and was cut flat along the bottom by
/// whatever the page drew next. Measured down the plate's centre: above it the
/// luminance climbs 0.957 → 0.975 over 8 pt, below it the pixel under the plate
/// is already the page's white. Light that falls off on three sides and stops
/// dead on the fourth does not read as light.
///
/// And a linear ramp is not how anything glows. `RadialGradient` interpolates
/// at a constant rate, so the disc has a visible rim where the ramp ends,
/// however faint the colour is. A shadow is a Gaussian blur — no rim, nothing
/// to see the end of, and small enough (7 pt of blur, 4 pt down at the default
/// size) to sit inside the header's own padding rather than reaching past it.
///
/// This is also the small tile in the panel and the order list — the same
/// drawing at several sizes, which had been copy-pasted at three sites with
/// their own radii and glyph sizes. The settings sidebar draws `ShellGlyphView`,
/// not this.
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
    /// How much more was measured off System Settings rather than picked: its
    /// sidebar tile is 40 px and the ink inside it is 28 — the symbol fills
    /// **0.70** of the tile.
    ///
    /// The ratio has to be read off a real render, not computed. SwiftUI sizes
    /// a symbol against the font's metrics, so `.font(.system(size: 15))` paints
    /// about 1.34× that in ink; the old 0.55 was therefore filling 0.82 of the
    /// tile, which is what made the sidebar look crowded. Photographed and
    /// measured at 0.47: 41 px of ink in a 43 px tile became 30 in 44.
    private var glyphSize: CGFloat {
        let base: CGFloat = switch size {
        case ...32: size * 0.47
        default: size * 0.44
        }
        // Corrected per symbol: one point size across the set is 28% of visual
        // size between `keyboard` and `lock.shield`. `SymbolInk` has the
        // measurements.
        return base * SymbolInk.correction(for: symbol)
    }

    /// Measured off System Settings' own sidebar rather than guessed at, twice
    /// — the first attempt drew these flat, and they are not.
    ///
    /// A system tile is 18 pt and carries a vertical gradient: sampled down its
    /// centre, `71,153,247` at the top and `57,130,241` at the bottom. Around
    /// it is a neutral shadow, not a tinted one: the sidebar's `237,237,237`
    /// runs `234, 229, 218, 203` over the four pixels approaching the tile's
    /// side, and `204, 217, 227, 232, 235` over the six below it — deeper and
    /// longer underneath, which is a small downward offset.
    ///
    /// The ratios below were then tuned until Helm's own 22 pt tile produced the
    /// same profile: `237 → 227` over six pixels above it, and `207, 213, 217,
    /// 222, 225, 229, 233` over seven below — the system's shape, scaled.
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
            // Decoration at every one of its call sites: a title always sits
            // beside it. Left visible, the symbol announces its own raw name as
            // an extra stop before the heading it decorates — a dozen times
            // over, since this is the plate the whole app uses.
            .accessibilityHidden(true)
    }
}

/// A plate that carries a *verdict's* signal rather than a module's identity —
/// the orange warning or green check a page answers with.
///
/// It draws exactly what `HelmIconPlate` draws (it is one), so the look is
/// pixel-identical; it exists as its own name so that the two meanings stay
/// apart, and so that the tint it takes is a signal from `HelmSignal` or grey
/// and never a module's colour.
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
/// The system's own `Section("…")` draws 13 pt semibold in sentence case,
/// which puts a section heading at the same weight as the rows under it and
/// only two points below the page's own name. The redesign draws it as a label
/// rather than a title — 11 pt semibold in the quiet ink, sentence case, no
/// tracking — so the eye reads the group as a group and the page keeps one
/// title.
///
/// It is not uppercased; the body says why the capitals went.
public struct HelmSectionTitle: View {
    private let title: String
    public init(_ title: String) { self.title = title }

    public var body: some View {
        // v3's `.sectitle`: 11 pt semibold, quiet, and **not** uppercased.
        //
        // It was 10 pt capitals with 0.8 of tracking. Capitals are a second
        // voice — the app used them for the badge and for the metric strip's
        // labels, where a word is a token rather than a word — and a section
        // heading is neither: it names the thing below it, in the same voice
        // the rows are written in. At 10 pt the capitals also needed the
        // tracking to stay legible, which is the size telling you it is one
        // step too small for the job.
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(HelmText.quiet)
            // A heading over rows is a heading to the rotor, said once here so a
            // call site cannot forget it.
            // The trait is a set: a site or a `Section(header:)` that says it
            // again changes nothing.
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

    /// Static so the fraction can be measured rather than described: a blend
    /// depth is a contrast decision, and the last one was made against
    /// `.tertiary` rather than against a floor. At 0.30 the figures measured
    /// **green 3.85:1, orange 3.99:1, teal 3.76:1** against the window in
    /// light, at 16 pt medium — which is body text by every threshold there
    /// is. At 0.40 they measure **4.80 / 4.97 / 4.69**.
    ///
    /// The tint is resolved in the light appearance explicitly rather than in
    /// whichever one `NSAppearance.current` happens to hold. `NSColor(Color)`
    /// asks the ambient appearance what a dynamic colour is, and this runs
    /// under `colorScheme == .light` taken from the *environment* — two
    /// different sources for one answer. Measured with the two disagreeing,
    /// the same 0.30 blend came out at 3.54 / 3.87 / 3.27, because it had
    /// darkened dark mode's brighter green and called it a light-mode colour.
    /// A contrast that depends on which of the two won is not a contrast
    /// anybody measured.
    static func legible(_ tint: Color, in scheme: ColorScheme) -> Color {
        guard scheme == .light else { return tint }
        var darkened = NSColor(tint)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            // Both steps inside the block, and the conversion to sRGB before
            // the blend. `NSColor(Color)` hands back a *dynamic* colour, so
            // resolving it here and blending it outside resolves it a second
            // time against whatever appearance is current then — which is the
            // bug this block exists to close, reintroduced one line lower.
            let base = NSColor(tint).usingColorSpace(.sRGB) ?? NSColor(tint)
            darkened = base.blended(withFraction: 0.40, of: .black) ?? base
        }
        return Color(nsColor: darkened)
    }

    public struct Metric: Identifiable {
        /// The label, not a fresh UUID: metrics are rebuilt inline from view
        /// model state, and a new identity on every publish made `ForEach` tear
        /// down and re-create every cell instead of updating it.
        public var id: String { label }
        public let value: String
        public let label: String
        public let tint: Color?

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
                        // Figures roll rather than cut. The ring already did
                        // this; every other live number in the app did not,
                        // and Keep Awake's is a countdown at 1 Hz.
                        .contentTransition(.numericText())
                        .animation(HelmMotion.interface, value: metric.value)
                        // A system tint is built for a dark background: the same
                        // green measured 8.25:1 in dark and 2.22:1 in light.
                        // Darkened in light appearance so the figure is legible
                        // in both, rather than legible in one — see `legible`
                        // for how far, and for what it measures after.
                        .foregroundStyle(metric.tint.map { Self.legible($0, in: traits.scheme) } ?? .primary)
                    Text(metric.label)
                        // 10, the scale's bottom step. It was 9 — a size on no
                        // step, under a figure that is on one, in the strip
                        // that About draws.
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // `.tertiary` at 9 pt measured 1.87:1 light and 2.26:1
                        // dark — below every threshold, on a strip that appears
                        // on About.
                        // The token, not a hand-picked opacity. 0.6 was chosen
                        // to beat `.tertiary`'s 1.87:1 and stopped at 4.09:1,
                        // short of the 4.5 these tokens exist to clear.
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
