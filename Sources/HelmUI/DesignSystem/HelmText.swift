import AppKit
import SwiftUI

/// Text that recedes, at contrasts that were measured rather than assumed.
///
/// SwiftUI's `.tertiary` measures **1.88:1** against the window in light and
/// 2.26:1 in dark; `.quaternary` measures 1.25:1 and 1.34:1. Both are below
/// every readability threshold there is. `HelmMetricStrip`'s label style
/// records the same finding in place (1.87:1 at 9 pt); these tokens are the
/// general fix. They are literal colours, which also keeps them out of the
/// hierarchical-style hazard that the Motion rules warn about inside animated
/// blocks.
///
/// The ratios below are measured (`Scripts/design/contrast.swift`) against
/// what the app draws, not against pure black on pure white: `Color.primary`
/// is `labelColor`, which is 85% black, and it lands on
/// `windowBackgroundColor`. Arithmetic against pure black on pure white is too
/// generous — 0.60 measures 4.09:1 rather than 5.74:1, and 0.45 measures
/// 2.69:1 rather than 3.35:1, below the threshold it would claim to clear. The
/// opacities are solved for the target in the worse of the two appearances
/// rather than chosen and described afterwards.
///
/// **Four settings sizes, not more.** Text sizes and weights chosen a call
/// site at a time drift apart. The ones under "The settings type
/// scale" are what macOS's own settings use for the same jobs, so a Helm page
/// and a System Settings pane read at the same rhythm — and a size that is not
/// there is a decision somebody has to argue for rather than type.
public enum HelmText {
    /// Secondary copy inside cards and rows: body text that happens to be
    /// quieter, so it answers to the body threshold. 4.92:1 light, 6.06:1 dark
    /// — where the platform's own `.secondary` is 3.95:1 light.
    ///
    /// **0.66, because 0.64 is not enough on a tinted field.** The four
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
    /// with it. It also keeps `quiet` above `faint`, which 0.64 would not:
    /// `faint` at 0.65 would be the darker of the two.
    public static let quiet = Color.primary.opacity(0.66)
    /// Ink on a saturated fill — the accent, a signal colour, a module's tint — where `Color.primary`
    /// would turn dark on the fill in light and lose it.
    public static let onFill = Color.white
    /// What a window that is not the active one draws its text and glyphs at (`\.helmWindowAppearsActive`):
    /// the header row and the sidebar's rows. Not a reading floor — it says "this window is not in
    /// front", as System Settings' sidebar does; the fill under it stays.
    public static let inactiveOpacity = 0.6
    /// Captions that must recede and stay readable — short, and never the only
    /// place a fact appears. 4.77:1 / 5.92:1.
    ///
    /// 0.55 measures 3.54:1 in light — under the body floor. The floor needs
    /// 0.631; 0.65 is the first step past it.
    public static let faint = Color.primary.opacity(0.65)
    /// Marks, never text — breadcrumb chevrons and the like. A chevron carries
    /// meaning, so it answers to the 3:1 non-text threshold rather than to
    /// nothing at all. 3.07:1 / 4.07:1.
    public static let separator = Color.primary.opacity(0.50)

    /// A figure: a byte size, a count, a version — anything whose digits a
    /// reader compares down a column rather than reads as a word.
    ///
    /// Sizes drawn in four faces across lists that sit next to each other in
    /// the same sidebar disagree. Measured, "1,24 ГБ" at SF Mono 11 renders 27% wider
    /// than at SF Pro 10 with tabular figures, so two such columns cannot be
    /// made to agree by choosing a width — they disagree about the glyphs.
    ///
    /// **SF Pro with tabular figures, not SF Mono.** A mono face keeps a number
    /// and its unit at one rhythm — but so does the interface face with
    /// `monospacedDigit()`, which is what macOS itself sets a size in, and SF
    /// Mono reads as what it is everywhere else in this app: code. A byte size
    /// in a settings row is not code. The digits still do not jump as they
    /// change, which is the whole requirement; `.monospacedDigit()` is **on the
    /// token**, so a caller that spells `.font(HelmText.figureFont)` without
    /// reaching for `helmFigure()` gets it too.
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
    /// A token because it is used twice: the metric strip that rides every
    /// module page, and VPN's tile strip. Both also cap the line and let it
    /// shrink, which is why the whole treatment is `helmMetricFigure()` rather
    /// than this size alone.
    ///
    /// **The tabular digits are on the token, not on the modifier.**
    /// `helmMetricFigure()` caps the line and lets it shrink and does not ask
    /// for `monospacedDigit()` at all; a headline figure that jumps as it counts
    /// is what that would cost on a face that is not already tabular.
    public static let metricFont = Font.system(size: 16, weight: .medium).monospacedDigit()

    /// The scale's top step: the one line a page leads with, whatever it says.
    ///
    /// Keep Awake's four states, VPN's verdict and its empty slot, Layout's
    /// count — three modules share one 40 pt light line, so two pages of this
    /// app do not measure their own heroes differently. A reason like that
    /// belongs on a token, not in a sentence at a call site.
    ///
    /// Held rather than built at the call site for the ordinary reason a value
    /// with no argument is: it is one value and there is one of it. What that
    /// saves is small, and measured rather than assumed — 330 ns and no
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
    /// width. Not a monospaced *face*, which buys the same thing and makes a
    /// countdown look like code.
    public static let heroFigureFont = heroFont.monospacedDigit()
    /// The tracking a hero figure takes; a sentence in the same slot takes none.
    public static let heroFigureTracking: CGFloat = -2

    // MARK: - The settings type scale

    /// A row's own name: the thing the row is about. macOS's settings rows.
    ///
    /// **And a sentence on a page, which is the same decision.** 13 is what
    /// macOS resolves `.body` to, so a paragraph, a hint and a row's name are
    /// one size — and `.callout` (12) to mean «body, but a little quieter» is a
    /// fifth size on a window the scale gives four and a distinction nobody can
    /// see. Quieter is
    /// what `HelmText.quiet` is for. A *fifth token* spelling 13 a second time
    /// would be a synonym, and a scale exists to have fewer of those.
    ///
    /// **Named, not numbered.** `.system(size: 13)` and `.system(size: 11)` are
    /// the same face at a size that never moves — so a Mac whose owner raised
    /// the interface text size would get a Helm window that does not follow. The styles below resolve to the very same
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
    /// `rowDetail` as AppKit sees it, for the two places that measure text
    /// rather than draw it (`LeftoverPathFloor`, `TabStripFit`).
    ///
    /// A font rather than a number: the two sides have to agree about the *same*
    /// text style — a bare 11 would keep measuring 11 while the drawn line grows
    /// with the system's setting, and the floor would be under the thing it holds
    /// up.
    public static var rowDetailNSFont: NSFont { .preferredFont(forTextStyle: .subheadline) }
    /// The heading over a card, on the page rather than inside it.
    public static let sectionHeading = Font.body.weight(.semibold)
    /// The heading of a group *inside* a list — the sidebar's own section
    /// labels, and the copies of them the composer draws.
    public static let groupLabel = Font.subheadline.weight(.semibold)
    /// The state glyph at the start of a status line (About's update card): `.title3`, 15 pt at the default.
    public static let statusGlyph = Font.title3
    /// The fine print at the foot of a page and a group heading on a panel card: `.caption2`, 10 pt at the default.
    public static let smallPrint = Font.caption2
    /// A tick label under a picture: `.caption`, 10 pt at the default.
    public static let pictureCaption = Font.caption
    /// The version over a changelog entry: `.title3` bold, 15 pt at the default.
    public static let entryHeading = Font.title3.weight(.bold)
    /// A title set beside an icon plate or over a short body: an editor sheet's name, a verdict, a page's own title, an empty state's heading, a sheet's or a tour step's title. A fixed size, 16 pt, the scale's step above body.
    public static let plateTitle = Font.system(size: 16, weight: .semibold)
    /// What is inside is not language but something to be typed exactly (a command, a path); a text
    /// style, so it is 11 pt at the default and follows the system's size.
    public static let code = Font.system(.subheadline, design: .monospaced)
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
