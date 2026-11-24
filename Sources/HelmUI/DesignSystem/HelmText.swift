import AppKit
import SwiftUI

/// Text that recedes, at contrasts measured against what the app draws.
///
/// SwiftUI's `.tertiary` and `.quaternary` fall below every readability
/// threshold against the window (about 1.9:1 and 1.3:1 in light). These tokens
/// are literal colours, which also keeps them clear of the hierarchical-style
/// hazard inside animated blocks (Architecture/DesignSystem.md § Motion).
///
/// The ratios are measured against `Color.primary` as drawn, `labelColor` at
/// 85% black on `windowBackgroundColor`, not pure black on pure white, which is
/// too generous. Each opacity is solved for its floor in the worse of the two
/// appearances.
///
/// Four settings sizes, the ones macOS's own settings use for the same jobs
/// (Architecture/DesignSystem.md § Type).
public enum HelmText {
    /// Secondary copy inside cards and rows, held to the body threshold: 4.92:1
    /// light, 6.06:1 dark, where the platform's `.secondary` is 3.95:1 light.
    ///
    /// 0.66, not 0.64, because of `HelmBanner`, which writes this ink on its
    /// signal colour at 13 %, a ground stricter than the page's four surfaces in
    /// both appearances. 0.64 falls under the body floor there, and lowering the
    /// banner's fill cannot fix it before the field stops reading as a field.
    /// 0.66 clears every banner reading and keeps `quiet` above `faint`.
    public static let quiet = Color.primary.opacity(0.66)
    /// Ink on a saturated fill — the accent, a signal colour, a module's tint — where `Color.primary`
    /// would turn dark on the fill in light and lose it.
    public static let onFill = Color.white
    /// What a window that is not the active one draws its text and glyphs at (`\.helmWindowAppearsActive`):
    /// the header row and the sidebar's rows. Not a reading floor — it says "this window is not in
    /// front", as System Settings' sidebar does; the fill under it stays.
    static let inactiveOpacity = 0.6
    /// Captions that must recede and stay readable — short, and never the only
    /// place a fact appears. 4.77:1 / 5.92:1; the body floor needs 0.631, and
    /// 0.65 is the first step past it.
    public static let faint = Color.primary.opacity(0.65)
    /// Marks, never text — breadcrumb chevrons and the like. A chevron carries
    /// meaning, so it answers to the 3:1 non-text threshold rather than to
    /// nothing at all. 3.07:1 / 4.07:1.
    public static let separator = Color.primary.opacity(0.50)

    /// A figure: a byte size, a count, a version — anything whose digits a
    /// reader compares down a column rather than reads as a word.
    ///
    /// SF Pro with tabular figures, not SF Mono: macOS sets a size in the
    /// interface face, and SF Mono reads as code everywhere else in this app.
    /// One face for every list, because figures in two faces cannot be made to
    /// agree by choosing a width. `.monospacedDigit()` is on the token, so a
    /// caller that spells `.font(HelmText.figureFont)` gets it too. Named, not
    /// numbered, so the window follows a raised interface text size.
    public static let figureFont = Font.subheadline.monospacedDigit()

    /// The headline figure of a metric or a tile: the scale's step above body,
    /// in `figureFont`'s voice. Used by the metric strip and VPN's tile strip,
    /// both through `helmMetricFigure()`, which caps the line and lets it shrink
    /// but asks for no tabular digits: those are on the token.
    public static let metricFont = Font.system(size: 16, weight: .medium).monospacedDigit()

    /// The scale's top step: the one line a page leads with, whatever it says.
    /// Keep Awake's states, VPN's verdict and Layout's count share it, so no two
    /// pages measure their heroes differently. The size does not travel with
    /// `helmHeroSentence()`: what the slots share there is how a line wraps.
    public static let heroFont = Font.system(size: 40, weight: .light)

    /// The same step when the hero is a number: a countdown, a count. Tabular
    /// digits, for `figureFont`'s reason, so a figure redrawn each second does
    /// not shuffle its neighbours.
    public static let heroFigureFont = heroFont.monospacedDigit()
    /// The tracking a hero figure takes; a sentence in the same slot takes none.
    public static let heroFigureTracking: CGFloat = -2

    // MARK: - The settings type scale

    /// A row's own name, and a sentence on a page: 13 is what macOS resolves
    /// `.body` to, so a paragraph, a hint and a row's name are one size, and
    /// "quieter" is `HelmText.quiet`, not `.callout`'s fifth size.
    ///
    /// Named text styles rather than numbers, so a Mac whose owner raised the
    /// interface text size gets a Helm window that follows; at the default they
    /// resolve to the same points (`.body` 13, `.subheadline` 11).
    ///
    /// `.headline` is not the heading here: on macOS it resolves to 13 bold, not
    /// semibold, a weight change no layout test would catch.
    public static let rowTitle = Font.body
    /// The line under a row's name, and the note under a group: secondary copy
    /// that a reader takes in after the thing it describes.
    public static let rowDetail = Font.subheadline
    /// `rowDetail` as AppKit sees it, for AppKit code that works at this size.
    ///
    /// A font rather than a number: the two sides have to agree about the *same*
    /// text style — a bare 11 would keep measuring 11 while the drawn line grows
    /// with the system's setting, and `LeftoverPathFloor` would sit under the thing it holds up.
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

extension View {
    /// The quiet detail line: `HelmText.rowDetail` in `HelmText.quiet`.
    public func helmQuietDetail() -> some View {
        font(HelmText.rowDetail).foregroundStyle(HelmText.quiet)
    }

    /// A figure, in the one face figures are set in. See `HelmText.figureFont`.
    public func helmFigure() -> some View {
        font(HelmText.figureFont)
            // Digits that change in place must not shift the ones beside them:
            // a size in a list is refreshed while the pointer is over it.
            .monospacedDigit()
    }

    /// A headline figure in a metric or a tile. See `HelmText.metricFont`.
    /// The cap and the floor travel with the face: a language widens the
    /// column, and a figure that wrapped would take the tile beside it down.
    public func helmMetricFigure() -> some View {
        font(HelmText.metricFont)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
