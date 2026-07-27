import SwiftUI

/// The surfaces that give every Helm screen the same voice as the About page:
/// one icon plate, instrument-style figures, and one card treatment.
public enum HelmSurface {
    public static let cardRadius: CGFloat = 12
    /// Measured against a real `Form` section on the same background: at 0.05
    /// the card sat 10 L from the panel where the system's section sits 7, in
    /// both themes — a heavier card claiming to be the same surface.
    public static let cardFill = Color.primary.opacity(0.035)
    /// A recessed area *inside* a card: console output, an unselected swatch.
    public static let wellFill = Color.primary.opacity(0.05)
    /// The same idea on a panel card, which already sits at 0.06 — a well
    /// there has to be heavier to read as recessed at all.
    public static let onPanelFill = Color.primary.opacity(0.08)
    /// A card on the panel's glass. Heavier than `cardFill` because glass
    /// gives less to sit against than a window background does.
    public static let panelCardFill = Color.primary.opacity(0.06)
    public static let hairline = Color.primary.opacity(0.10)
    /// For things that float *over* content — a tooltip following the cursor.
    /// Cards sit in the page and take no border (see `helmCard`); a floating
    /// surface has nothing behind it to sit against, so it keeps the hairline.
}

public extension View {
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
                RoundedRectangle(cornerRadius: HelmSurface.cardRadius, style: .continuous)
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
/// This is also the small tile in the panel, the sidebar and the order list —
/// the same drawing at 20, 22 and 26 pt, which had been copy-pasted at three
/// sites with their own radii and glyph sizes. Those are drawn flat: see
/// `isHero`.
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
    /// that proportion stops being legible — so the smaller tiles give the
    /// symbol more of the square. The ratios reproduce the sizes the
    /// hand-written copies used: 11 pt in a 20 pt tile, 13 in the panel's 26,
    /// 19.4 in a 44 pt plate.
    private var glyphSize: CGFloat {
        switch size {
        case ...24: size * 0.55
        case ...32: size * 0.50
        default: size * 0.44
        }
    }

    /// A tile in a row is a marker; a plate at the top of a page is an icon.
    /// System Settings draws the first flat — its sidebar tiles have no shadow
    /// and no gradient, at any size — and Control Center does the same in its
    /// rows. Lighting a 20 pt square in a list makes the list look embossed,
    /// not the square look real. Above row size the plate stops being a marker
    /// and starts standing for the page, and that is where the light belongs.
    private var isHero: Bool { size > 32 }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: glyphSize, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(fill)
            )
            // Tinted rather than black: the plate keeps its colour relationship
            // with the page without painting a ring of it. Dropped when the
            // tile is off, since an unlit thing casts nothing.
            .shadow(color: tint.opacity(isHero && active ? 0.30 : 0),
                    radius: size * 0.16, y: size * 0.09)
    }

    private var fill: AnyShapeStyle {
        guard active else { return AnyShapeStyle(Color.secondary.opacity(0.45)) }
        return isHero ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint)
    }
}

/// A screen's masthead: icon plate, title, one line of what the screen is for,
/// and whatever control belongs at the far end (usually the on/off switch).
/// The width of a settings page's content, and where it sits.
///
/// A grouped `Form` on macOS caps its own content at about 704 pt and centres
/// what is left over. Measured on a 950 pt page: uncapped, the card came out
/// 684 pt wide starting 383 pt from the left, so its leading edge walked away
/// from the header as the window grew. Capping the form and pinning it left
/// fixed the drift and left the whole surplus as one empty band down the right
/// side of the window, which reads as a page that failed to lay out.
///
/// The column cannot be made wider — that limit is the form style's, not ours.
/// So it is centred, with the header centred on the same column, and the page
/// reads as one deliberate column rather than as content stuck to one edge.
/// This is what System Settings does with its own window.
public extension View {
    func helmSettingsColumn() -> some View {
        frame(maxWidth: HelmLayout.settingsColumn)
            .frame(maxWidth: .infinity)
    }
}

public enum HelmLayout {
    /// 704 of content plus the form's own 20 pt inset on each side.
    public static let settingsColumn: CGFloat = 744
}

/// Text that recedes, at contrasts that were measured rather than assumed.
///
/// SwiftUI's `.tertiary` measures **1.88:1** against the window in light and
/// 2.26:1 in dark; `.quaternary` measures 1.25:1 and 1.34:1. Both are below
/// every readability threshold there is, and both were in use at sixteen
/// sites. `HelmMetricStrip` found this once and fixed it in place — the
/// comment at its label style records 1.87:1 at 9 pt — and the fix was never
/// generalised. These are literal colours, which also keeps them out of the
/// hierarchical-style hazard that the Motion rules warn about inside animated
/// blocks.
public enum HelmText {
    /// Secondary copy inside cards and rows. 5.74:1 light, 6.77:1 dark.
    public static let quiet = Color.primary.opacity(0.60)
    /// Captions that must recede and stay readable. 3.35:1 / 4.41:1.
    public static let faint = Color.primary.opacity(0.45)
    /// Marks, never text — breadcrumb chevrons and the like. 2.44:1 / 3.21:1.
    public static let separator = Color.primary.opacity(0.35)
}

public struct HelmPageHeader<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    /// True for a page whose content spans the pane rather than sitting in the
    /// 744 pt form column — Disk, Uninstaller, Homebrew, Leftovers.
    let bleeds: Bool
    let trailing: Trailing

    public init(symbol: String, tint: Color, title: String, subtitle: String,
                bleeds: Bool = false,
                @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.subtitle = subtitle
        self.bleeds = bleeds
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 14) {
            HelmIconPlate(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.2)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        // 20, matching the inset a grouped Form uses at every width.
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        // On the same column as the content below it. Which column that is
        // depends on the page: a grouped Form is capped at 744 pt and centred,
        // so its header is too — but a full-bleed page draws its toolbar at a
        // flat 20 pt inset across the whole pane, and a centred header above
        // it walks away as the window grows. Measured on a 1400 pt window: the
        // title sat 203 pt right of the controls beneath it, under a
        // full-width divider. It has never been seen because at the default
        // window the pane is 690 pt — narrower than the column, where the two
        // rules agree.
        .frame(maxWidth: bleeds ? .infinity : HelmLayout.settingsColumn)
        .frame(maxWidth: .infinity, alignment: bleeds ? .leading : .center)
    }
}

/// Instrument readout: monospaced figures over small-caps labels, split by
/// hairlines — the About page's version/build/modules row, generalized.
public struct HelmMetricStrip: View {
    /// Keeps a tint readable on a light background without inventing a palette:
    /// the system colours are chosen for dark, and the light theme is where
    /// they fail.
    @Environment(\.colorScheme) private var colorScheme

    private func legible(_ tint: Color) -> Color {
        guard colorScheme == .light else { return tint }
        return Color(nsColor: NSColor(tint).blended(withFraction: 0.30, of: .black) ?? NSColor(tint))
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
                VStack(spacing: 3) {
                    Text(metric.value)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        // Figures roll rather than cut. The ring already did
                        // this; every other live number in the app did not,
                        // and Keep Awake's is a countdown at 1 Hz.
                        .contentTransition(.numericText())
                        .animation(HelmMotion.interface, value: metric.value)
                        // A system tint is built for a dark background: the same
                        // green measured 7.67:1 in dark and 2.03:1 in light.
                        // Darkened in light appearance so the figure is legible
                        // in both, rather than legible in one.
                        .foregroundStyle(metric.tint.map(legible) ?? .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(metric.label)
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.7)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        // `.tertiary` at 9 pt measured 1.87:1 light and 2.26:1
                        // dark — below every threshold, on a strip that appears
                        // on every module page.
                        .foregroundStyle(Color.primary.opacity(0.6))
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
