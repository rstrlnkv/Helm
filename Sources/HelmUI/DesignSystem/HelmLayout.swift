import SwiftUI

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
/// that is not itself a scroller and would otherwise take the whole pane. The
/// other half of the lesson is that *widening* the scroller is not the repair:
/// SwiftUI hit-tests a scroll view's content region, so `safeAreaPadding`
/// leaves the sides as dead.
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

    /// A full-width strip of a page that bleeds across the pane: the form inset
    /// across, one `s5` step down.
    func helmPageStrip() -> some View {
        padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }
}

public enum HelmLayout {
    /// 704 of content plus the form's own inset on each side.
    public static let settingsColumn: CGFloat = 744

    /// What a grouped `Form` insets its section cards by, each side. Spelled
    /// out because two numbers on this page are derived from it rather than
    /// typed: the card row's width, and the widest a card in it may grow.
    public static let formInset: CGFloat = 20

    /// The column a row's mark (and a log row's severity glyph) is drawn in: 14, from `.rspace { flex: 0 0 14px }`.
    /// A card of mixed rows keeps one left edge for its labels because every mark column is this wide.
    public static let markColumn: CGFloat = 14

    /// The leading SF Symbol column of a row: the icon is centred in it, so rows of different symbols keep one
    /// left edge for their labels.
    public static let symbolColumn: CGFloat = 18

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
    /// A number owned by SwiftUI, which a macOS release
    /// can move.
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
    /// Also SwiftUI's number rather than ours.
    public static let groupedHeaderGap: CGFloat = 10

    /// The widest a column of prose, facts or fields may be drawn — for the
    /// panes that are **not** a grouped `Form` and therefore have nothing
    /// capping them.
    ///
    /// `settingsColumn` is the other half of this story and does not answer
    /// here: 744 is a page's width in a window, and the places that need this
    /// are second columns inside a page. Homebrew's inspector is the one that
    /// made it visible — nothing in it was bounded, so at the pane the app
    /// actually draws (measured 2026-09-15: a 1210 pt window, a 984 pt module
    /// pane, a 310 pt master) it was handed 649 pt and everything inside it
    /// stretched to fill: a tile holding `2.11.4` came out 308 pt wide and a
    /// sentence ran the full 625 pt of content.
    ///
    /// **444, and it is the same number from three directions.** A reading
    /// measure is 60–75 characters; measured on macOS 27, `HelmText.rowDetail`
    /// (`.subheadline`, 11 pt) averages 5.89 pt per lowercase letter, so 75 of
    /// them are 442, and `HelmText.rowTitle` (`.body`, 13 pt) averages 6.81, so
    /// 65 of them are 442 as well. The approved drawing this module was built
    /// from puts its inspector at 472 pt with 14 pt of padding each side, which
    /// is 444 of content. Being the *maximum*, it only ever narrows a pane that
    /// is wider: below it nothing is gated, which is what keeps a control from
    /// being reachable only on a big screen.
    ///
    /// Left-aligned at the call site rather than centred, unlike
    /// `helmSettingsColumn`: a second column that centres its content leaves a
    /// gutter on the side it shares with the master list, and the two columns
    /// then read as drifting apart.
    public static let readingColumn: CGFloat = 444
}
