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
/// sites with their own radii and glyph sizes.
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
            .foregroundStyle(.white)
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
///
/// The ratios below replace the ones this comment used to carry, which were
/// arithmetic done against pure black on pure white. Neither is what the app
/// draws: `Color.primary` is `labelColor`, which is 85% black, and it lands on
/// `windowBackgroundColor`. Measured properly (`Scripts/design/contrast.swift`)
/// the old 0.60 was 4.09:1 rather than the 5.74:1 written here, and 0.45 was
/// 2.69:1 rather than 3.35:1 — the second one below the threshold it claimed
/// to clear. The opacities are now solved for the target in the worse of the
/// two appearances rather than chosen and described afterwards.
public enum HelmText {
    /// Secondary copy inside cards and rows: body text that happens to be
    /// quieter, so it answers to the body threshold. 4.62:1 light, 5.78:1 dark
    /// — where the platform's own `.secondary` is 3.95:1 light.
    public static let quiet = Color.primary.opacity(0.64)
    /// Captions that must recede and stay readable — short, and never the only
    /// place a fact appears. 3.54:1 / 4.63:1.
    public static let faint = Color.primary.opacity(0.55)
    /// Marks, never text — breadcrumb chevrons and the like. A chevron carries
    /// meaning, so it answers to the 3:1 non-text threshold rather than to
    /// nothing at all. 3.07:1 / 4.07:1.
    public static let separator = Color.primary.opacity(0.50)

    /// A figure: a byte size, a count, a version — anything whose digits a
    /// reader compares down a column rather than reads as a word.
    ///
    /// Sizes were drawn in four faces across lists that sit next to each other
    /// in the same sidebar. Measured, "1,24 ГБ" at SF Mono 11 renders 27% wider
    /// than at SF Pro 10 with tabular figures, so two such columns cannot be
    /// made to agree by choosing a width — they disagree about the glyphs.
    ///
    /// Monospaced rather than tabular-SF-Pro because the figures share their
    /// row with a unit («ГБ», "Mo") and a mono face keeps the number and its
    /// unit at one rhythm. 11 pt is the size the strip's own figures scale
    /// from, one step under body.
    public static let figureFont = Font.system(size: 11, design: .monospaced)
}

public extension View {
    /// A figure, in the one face figures are set in. See `HelmText.figureFont`.
    func helmFigure() -> some View {
        font(HelmText.figureFont)
            // Digits that change in place must not shift the ones beside them:
            // a size in a list is refreshed while the pointer is over it.
            .monospacedDigit()
    }
}

/// Colour that carries a meaning: this needs attention, this failed, this is on.
///
/// The same argument as `HelmText`, one class of colour over. The system
/// palette is tuned for dark, where all three are comfortable, and it is light
/// where they fail — measured with `Scripts/design/contrast.swift` against both
/// `windowBackgroundColor` and `controlBackgroundColor`, which are the same
/// colour on macOS 26:
///
///     light   orange 2.31:1   green 2.22:1   red 3.57:1
///     dark    orange 7.47:1   green 8.25:1   red 4.86:1
///
/// against a 4.5:1 body-text floor and a 3:1 floor for a mark that carries
/// meaning. So the icon on every "needs a permission" banner — the most
/// important warning the app has — was its least visible mark in light mode,
/// and `HelmHotkeyRecorder`'s "this shortcut does nothing" note was body text
/// at 2.31:1. This is the defect `HelmText` and `HelmBadge` were built to
/// eliminate, never generalised past text tokens.
///
/// One threshold rather than two: these are used for icons *and* for body text,
/// so they answer to the stricter one everywhere rather than to whichever the
/// current call site happens to need. The light values are the system colours
/// blended toward black by the smallest fraction that clears 4.5:1 (0.36, 0.38,
/// 0.15) — solved for, not chosen and described afterwards. Dark keeps the
/// system colours untouched: they already pass, and the palette macOS ships is
/// the one people recognise.
///
/// Resolved colours, not hierarchical styles, so they are safe inside the
/// measured-height blocks the Motion rules warn about.
public enum HelmSignal {
    /// Something needs attention and can still be acted on. 4.54:1 / 7.47:1.
    public static let warning = adaptive(
        light: NSColor(srgbRed: 0.700, green: 0.380, blue: 0.097, alpha: 1), dark: .systemOrange)
    /// Granted, done, up to date. 4.59:1 / 8.25:1.
    public static let success = adaptive(
        light: NSColor(srgbRed: 0.126, green: 0.529, blue: 0.227, alpha: 1), dark: .systemGreen)
    /// It failed. 4.52:1 / 4.86:1.
    public static let danger = adaptive(
        light: NSColor(srgbRed: 0.879, green: 0.188, blue: 0.202, alpha: 1), dark: .systemRed)

    /// One colour that answers for itself in either appearance, so no call site
    /// has to read the environment to stay legible.
    private static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
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
                    .foregroundStyle(HelmText.quiet)
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
                VStack(spacing: 3) {
                    Text(metric.value)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
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
                        .foregroundStyle(metric.tint.map { Self.legible($0, in: colorScheme) } ?? .primary)
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
