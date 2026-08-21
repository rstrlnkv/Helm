import AppKit
import SwiftUI

/// The surfaces that give every Helm screen the same voice as the About page:
/// one icon plate, instrument-style figures, and one card treatment.
public enum HelmSurface {
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
    /// A multi-line field that reads as a field.
    ///
    /// **The chrome is `TextEditor`'s own, and it is the problem.** SwiftUI draws
    /// an `NSTextView`'s scroll background — `textBackgroundColor`, which is
    /// white in light and near-black in dark — and inside a grouped `Form` that
    /// lands on a card of very nearly the same value: measured 1.02:1 in light
    /// and 1.18:1 in dark, against a 3:1 floor for anything that is not text.
    /// A person could not see where the box was. So the platform's own fill is
    /// hidden and the field is drawn as a well with an edge: the fill says
    /// «recessed», and the border is what actually carries the boundary — a
    /// difference of a few per cent in fill can never reach 3:1 whatever
    /// opacity it is given.
    ///
    /// Here rather than in the one page that has a `TextEditor` today, because
    /// the defect belongs to the control and not to the page: the second
    /// multi-line field anybody adds needs the same three decisions, and would
    /// otherwise be borderless again.
    func helmFieldWell() -> some View {
        scrollContentBackground(.hidden)
            // The text's own inset. Without it the first glyph sits on the
            // border, which is what a hidden scroll background takes away.
            .padding(HelmSpace.s3)
            .background(
                RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .fill(HelmSurface.wellFill)
            )
            .overlay(
                // `HelmText.separator`, not `HelmSurface.hairline`: a hairline
                // separates two rows of one list and measures 1.25:1 against
                // this well — right for what it does and useless as a boundary
                // somebody has to find. `separator` is the house's token for a
                // mark that carries meaning and answers to 3:1; measured here
                // with `Scripts/design/contrast.swift` it is 3.83:1 against the
                // well in light and 4.52:1 in dark, where the fill difference
                // this replaces was 1.08:1 and 1.10:1.
                RoundedRectangle(cornerRadius: HelmRadius.ctl, style: .continuous)
                    .strokeBorder(HelmText.separator)
            )
    }

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
/// This is also the small tile in the panel, the sidebar and the order list —
/// the same drawing at 20, 22 and 26 pt, which had been copy-pasted at three
/// sites with their own radii and glyph sizes.
public struct HelmIconPlate: View {
    /// How the person asked for module icons to be drawn. Read from the
    /// environment rather than taken as a parameter: this is the app's one
    /// module icon, drawn at nine call sites, and a preference passed at each of
    /// them is a preference eight of them can forget.
    @Environment(\.helmModuleIconStyle) private var style
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

    /// A bare glyph at the plate's own frame, for the person who asked for
    /// plain module icons.
    ///
    /// **Not the module's colour at a smaller dose**: a tinted glyph on the
    /// surface's own background reads as neither plate nor text. The plain look
    /// is grey, and the shape does the distinguishing — which is why it is
    /// bigger than the glyph inside a plate. 0.59 of the frame against the
    /// plate's 0.47, so a 22 pt row draws it at 13, the size the settings
    /// sidebar drew by hand for four months.
    ///
    /// Corrected by `SymbolInk` like the plate is: without it one point size is
    /// 28% of visual size across this set — `keyboard` paints 1,27 of its square
    /// and `lock.shield` 0,99 — and the icon that relies on shape alone is the
    /// one that can least afford the shapes to be different sizes.
    private var plain: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.59 * SymbolInk.correction(for: symbol),
                          weight: .medium))
            .foregroundStyle(active ? HelmText.quiet : HelmText.quiet.opacity(0.45))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    public var body: some View {
        if style == .plain { plain } else { plated }
    }

    private var plated: some View {
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
/// A grouped `Form` on macOS caps its own content at 704 pt and centres what is
/// left over, so a page built on one is on this column already. The header is
/// centred on the same column, and the page reads as one deliberate column
/// rather than as content stuck to one edge — which is what System Settings
/// does with its own window. The column cannot be made wider: that limit is the
/// form style's, not ours.
///
/// **Never on a `Form`, because the `Form` is the scroll view.** Four pages
/// applied it to theirs, which made the scroller 744 pt wide and centred in the
/// pane: on the default 1060 pt window, 50 pt down each side belonged to nothing
/// and the wheel there moved nothing. It bought nothing either — measured at
/// 679, 845, 1149 and 1400 pt panes, a bare grouped `Form` puts its card in the
/// same place, to the point, as a capped one. What is left for this is content
/// that is not itself a scroller and would otherwise take the whole pane.
/// `ThePaneTakesTheWheelAtItsEdgesTests` guards it, and reads the modifier
/// chains as well as the rendered pages, because the other half of the lesson is
/// that *widening* the scroller is not the repair: SwiftUI hit-tests a scroll
/// view's content region, so `safeAreaPadding` leaves the sides as dead.
public extension View {
    /// …and the content idles while its window is off screen, wherever it is
    /// mounted (`OffScreenIdle` has the numbers). A page whose root is a `Form`
    /// calls `helmIdlesOffScreen()` on its own, for the same reason and without
    /// the column.
    func helmSettingsColumn() -> some View {
        frame(maxWidth: HelmLayout.settingsColumn)
            .frame(maxWidth: .infinity)
            .helmIdlesOffScreen()
    }
}

public enum HelmLayout {
    /// 704 of content plus the form's own inset on each side.
    public static let settingsColumn: CGFloat = 744

    /// What a grouped `Form` insets its section cards by, each side. Spelled
    /// out because two numbers on this page are derived from it rather than
    /// typed: the card row's width, and the widest a card in it may grow.
    public static let formInset: CGFloat = 20

    /// The width a section card actually gets.
    public static var cardWidth: CGFloat { settingsColumn - formInset * 2 }

    /// How much further in a grouped `Form` insets a section **header** than
    /// the section's own card, so a block riding on a header can be put back
    /// level with the cards under it.
    ///
    /// Measured on macOS 27 at the settings column: the card runs 70…774 and
    /// header content starts at 80 — the form insets a section by 20 and a
    /// header by 30. Text is right where it belongs at 30, level with the
    /// **content** of the rows below (82); a *card* drawn there is not, and the
    /// VPN page draws real cards in a header. Two card systems on one page
    /// that miss each other by 10 pt is the kind of thing nobody can name and
    /// everybody sees.
    ///
    /// A number owned by SwiftUI, so `TheConnectionsLineUpWithTheCardsTests`
    /// photographs both edges and fails if a macOS release moves either.
    public static let groupedHeaderOutset: CGFloat = 10

    /// What a grouped `Form` puts between a section header and the section's
    /// own card — the vertical half of the same story as the outset above.
    ///
    /// A block that draws its *own* cards inside a header has to supply this
    /// itself, and the VPN page did not: photographed at the settings column on
    /// macOS 27, from the heading's cap top to the card's fill is 21 pt where
    /// the form draws the card and was 11 where the page drew it, so the
    /// connections read as having slipped up into their own title.
    ///
    /// Also SwiftUI's number rather than ours, so
    /// `ThePageKeepsOneRhythmTests` compares the two gaps off one photograph
    /// instead of asserting this constant against itself.
    public static let groupedHeaderGap: CGFloat = 10
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
    /// quieter, so it answers to the body threshold. 4.92:1 light, 6.06:1 dark
    /// — where the platform's own `.secondary` is 3.95:1 light.
    ///
    /// **It was 0.64, and 0.64 is not enough on a tinted field.** The four
    /// surfaces this token was solved against are the page's — window, control,
    /// and Helm's card and well on top of them — and there is a fifth that
    /// belongs to a component: `HelmBanner` writes this ink on its own signal
    /// colour at 13 %, which darkens the ground in light and lightens it in dark,
    /// so it is stricter than all four in both appearances. Measured there,
    /// 0.64 gave 4.44:1 on the window, 4.37:1 in a card and 4.34:1 in a well —
    /// three readings under the body floor, on the field this app puts every
    /// warning it has in.
    ///
    /// Lowering the *fill* cannot fix it: at 0.08, well past the point where the
    /// field stops reading as a field, a card still measures 4.45:1. So the ink
    /// moved, and 0.66 is the ladder step that clears all six banner readings
    /// (worst 4.60:1 light, 4.88:1 dark) while taking the four page surfaces up
    /// with it. It also puts `quiet` back above `faint`, which it had not been:
    /// `faint` was raised to 0.65 to clear its own floor and had quietly become
    /// the darker of the two.
    public static let quiet = Color.primary.opacity(0.66)
    /// Captions that must recede and stay readable — short, and never the only
    /// place a fact appears. 4.77:1 / 5.92:1.
    ///
    /// It was 0.55, which measured 3.54:1 in light — under the body floor, and
    /// written down as such in this comment for months, because prose is not a
    /// guard. `RecessedTextIsReadableTests` is, and the floor needs 0.631
    /// (`Scripts/design/contrast.swift`); 0.65 is the first step past it.
    public static let faint = Color.primary.opacity(0.65)
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
    /// **SF Pro with tabular figures since 2026-08-20, not SF Mono.** The old
    /// note argued a mono face keeps a number and its unit at one rhythm, and it
    /// does — but so does the interface face with `monospacedDigit()`, which is
    /// what macOS itself sets a size in, and SF Mono then reads as what it
    /// is everywhere else in this app: code. A byte size in a settings row is
    /// not code. The digits still do not jump as they change, which was the
    /// whole requirement; `.monospacedDigit()` is **on the token**, so a caller
    /// that spells `.font(HelmText.figureFont)` without reaching for
    /// `helmFigure()` gets it too — seven call sites do exactly that.
    ///
    /// 11 pt is the size the strip's own figures scale from, one step under
    /// body, and it is named rather than numbered for the reason the scale below
    /// is: a Mac whose owner raised the interface text size should get a Helm
    /// window that follows.
    public static let figureFont = Font.subheadline.monospacedDigit()

    /// The same instrument voice one step up: the **headline** figure of a
    /// metric or a tile, rather than one in a row of them. 16 is the scale's
    /// step above body, and the face is `figureFont`'s for the same reason —
    /// a number and its unit at one rhythm.
    ///
    /// A token because it was spelled twice: the metric strip that rides every
    /// module page, and VPN's tile strip. Both also cap the line and let it
    /// shrink, which is why the whole treatment is `helmMetricFigure()` rather
    /// than this size alone.
    ///
    /// **The tabular digits are on the token and were never on the modifier.**
    /// `helmMetricFigure()` capped the line and let it shrink and did not ask
    /// for `monospacedDigit()` at all — which cost nothing while the face was
    /// SF Mono and would have cost a headline figure that jumps as it counts
    /// the moment it stopped being.
    public static let metricFont = Font.system(size: 16, weight: .medium).monospacedDigit()

    /// The scale's top step: the one line a page leads with, whatever it says.
    ///
    /// Keep Awake's four states, VPN's verdict and its empty slot, Layout's
    /// count — three modules, seven sites, each of which typed
    /// `.system(size: 40, weight: .light)` where it stood. `LayoutSettingsPage`
    /// wrote the reason down as a sentence — «the same 40 pt light figure Keep
    /// Awake's hero draws, so two pages of this app do not measure their own
    /// heroes differently» — with nothing under it, which is what a token is
    /// for. `EveryHeroIsSetInOneFontTests` is the rest of that sentence.
    ///
    /// Held rather than built at the call site for the ordinary reason a value
    /// with no argument is: it is one value and there is one of it. What that
    /// saves is small and was measured rather than assumed — 330 ns and no
    /// retained bytes per build, so this is a duplication fix and not a
    /// performance one.
    ///
    /// The size does not travel with `helmHeroSentence()`, which says so at
    /// itself: what the three slots share is how a line behaves when it wraps.
    public static let heroFont = Font.system(size: 40, weight: .light)

    /// The same step when the hero is a *number*: a countdown, a count of
    /// things put right today.
    ///
    /// Tabular digits for the reason `figureFont` has them — a figure redrawn
    /// once a second must not shuffle the digits beside it as they change
    /// width. It was a monospaced *face* until 2026-08-20, which bought the
    /// same thing and made a countdown look like code.
    public static let heroFigureFont = heroFont.monospacedDigit()

    // MARK: - The settings type scale
    //
    // **Four sizes, because the window had six.** Counted across the settings
    // window and the block inside it: 10, 11, 12, 13 and 15 pt, in three
    // weights, chosen a call site at a time. The ones below are what macOS's
    // own settings use for the same jobs, so a Helm page and a System Settings
    // pane read at the same rhythm — and a size that is not here is a decision
    // somebody has to argue for rather than type.

    /// A row's own name: the thing the row is about. macOS's settings rows.
    ///
    /// **And a sentence on a page, which is the same decision.** 13 is what
    /// macOS resolves `.body` to, so a paragraph, a hint and a row's name are
    /// one size — and the app had been reaching for `.callout` (12) at thirty
    /// sites to mean «body, but a little quieter», which is a fifth size on a
    /// window the scale gives four and a distinction nobody can see. Quieter is
    /// what `HelmText.quiet` is for. A *fifth token* spelling 13 a second time
    /// would be a synonym, and a scale exists to have fewer of those.
    /// **Named, not numbered, since 2026-08-20.** These were `.system(size: 13)`
    /// and `.system(size: 11)`, which is the same face at a size that never
    /// moves — so a Mac whose owner had raised the interface text size got a
    /// Helm window that did not. The styles below resolve to the very same
    /// points at the default setting (measured on macOS 27: `.body` 13 regular,
    /// `.subheadline` 11 regular), and to larger ones when the system says so.
    ///
    /// **`.headline` is not the heading here, and that is measured too.** On
    /// macOS it resolves to 13 **bold**, not semibold, so mapping
    /// `sectionHeading` onto it would have weighted every heading in the app a
    /// step heavier with the size unchanged — which no test could have caught,
    /// because the size is what a layout measures. `.body.weight(.semibold)` is
    /// the same size scaled and the weight this app already drew.
    public static let rowTitle = Font.body
    /// The line under a row's name, and the note under a group: secondary copy
    /// that a reader takes in after the thing it describes.
    public static let rowDetail = Font.subheadline
    /// `rowDetail` as AppKit sees it, for the one place that measures text
    /// rather than drawing it (`LeftoverPathFloor`).
    ///
    /// A font rather than the number it used to be. The two sides have to agree
    /// about the *same* text style now: a bare 11 would keep measuring 11 while
    /// the drawn line grew with the system's setting, and the floor would be
    /// under the thing it was holding up.
    public static var rowDetailNSFont: NSFont { .preferredFont(forTextStyle: .subheadline) }
    /// The heading over a card, on the page rather than inside it.
    public static let sectionHeading = Font.body.weight(.semibold)
    /// The heading of a group *inside* a list — the sidebar's own section
    /// labels, and the copies of them the composer draws.
    public static let groupLabel = Font.subheadline.weight(.semibold)
}

public extension View {
    /// A figure, in the one face figures are set in. See `HelmText.figureFont`.
    func helmFigure() -> some View {
        font(HelmText.figureFont)
            // Digits that change in place must not shift the ones beside them:
            // a size in a list is refreshed while the pointer is over it.
            .monospacedDigit()
    }

    /// A headline figure in a metric or a tile. See `HelmText.metricFont`.
    ///
    /// The cap and the floor travel with the face: these figures sit in a
    /// column that a language widens — «1,2 ГБ» against "1.2 GB" — and one
    /// that wrapped instead of shrinking would take the tile beside it down
    /// with it.
    func helmMetricFigure() -> some View {
        font(HelmText.metricFont)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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

/// The strip at the top of every page: what this page is, and the controls
/// that belong to the page rather than to any row in it.
///
/// **No summary line.** It carried the module's one-sentence description under
/// the name — «Не давать Mac засыпать» under «Не спать» — which is the sidebar
/// row you just clicked, said again in more words. Every mockup in the
/// redesign draws the plate, the name, and then the page's own controls; the
/// sentence still has two homes where it is the answer rather than an echo:
/// the empty state of a module that is switched off, and the composer's
/// tooltip.
/// The heading over a group of rows: small, upper case, spaced, quiet.
///
/// The system's own `Section("…")` draws 13 pt semibold in sentence case,
/// which puts a section heading at the same weight as the rows under it and
/// only two points below the page's own name. The redesign draws it as a label
/// rather than a title — `--t-micro`, upper case, .08em of tracking — so the
/// eye reads the group as a group and the page keeps one title.
///
/// Upper case is done by the string, not by a font trait: `.textCase(.uppercase)`
/// on a `Form` section is the platform's own styling and would fight this.
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
                        .foregroundStyle(metric.tint.map { Self.legible($0, in: colorScheme) } ?? .primary)
                    Text(metric.label)
                        // 10, the scale's bottom step. It was 9 — a size on no
                        // step, under a figure that is on one, in the strip
                        // that appears on every module page.
                        .font(.system(size: 10, weight: .semibold))
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
