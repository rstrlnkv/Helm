import SwiftUI

/// The width of a settings page's content, and where it sits.
///
/// A grouped `Form` on macOS caps its own content at 704 pt and centres what is
/// left over, so a page built on one is on this column already, and the header
/// is centred on the same column, as System Settings does. The cap is the form
/// style's and cannot be widened.
///
/// **Never on a `Form`, because the `Form` is the scroll view**: capped, the
/// scroller is centred in the pane and the wheel does nothing over the sides,
/// while a bare grouped `Form` puts its card in the same place anyway. Widening
/// the scroller with `safeAreaPadding` does not repair it, since SwiftUI
/// hit-tests a scroll view's content region. This is for content that is not
/// itself a scroller and would otherwise take the whole pane.
extension View {
    /// …and the content idles while its window is off screen (`OffScreenIdle`).
    /// A page whose root is a `Form` calls `helmIdlesOffScreen()` on its own,
    /// without the column.
    public func helmSettingsColumn() -> some View {
        frame(maxWidth: HelmLayout.settingsColumn)
            .frame(maxWidth: .infinity)
            .helmIdlesOffScreen()
    }

    /// A full-width strip of a page that bleeds across the pane: the form inset
    /// across, one `s5` step down.
    public func helmPageStrip() -> some View {
        padding(.horizontal, HelmLayout.formInset).padding(.vertical, HelmSpace.s5)
    }
}

public enum HelmLayout {
    /// 704 of content plus the form's own inset on each side.
    static let settingsColumn: CGFloat = 744

    /// What a grouped `Form` insets its section cards by, each side. Spelled
    /// out because two numbers on this page are derived from it rather than
    /// typed: the card row's width, and the widest a card in it may grow.
    public static let formInset: CGFloat = 20

    /// The column a row's mark (and a log row's severity glyph) is drawn in. A card of mixed rows keeps one left
    /// edge for its labels because every mark column is this wide.
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
    /// The form insets a section by 20 and its header by 30, which puts header
    /// text level with the rows' content but a *card* drawn in a header 10 pt
    /// off the cards below it (the VPN page draws real cards there). SwiftUI's
    /// number, which a macOS release can move.
    public static let groupedHeaderOutset: CGFloat = 10

    /// What a grouped `Form` puts between a section header and the section's
    /// own card — the vertical half of the same story as the outset above.
    ///
    /// A block that draws its own cards inside a header has to supply this
    /// itself, or the cards read as having slipped up into their own title.
    /// Also SwiftUI's number rather than ours.
    public static let groupedHeaderGap: CGFloat = 10

    /// The widest a column of prose, facts or fields may be drawn — for the
    /// panes that are **not** a grouped `Form` and therefore have nothing
    /// capping them.
    ///
    /// `settingsColumn` does not answer here: 744 is a page's width in a
    /// window, and this is for second columns inside a page, such as Homebrew's
    /// inspector, where nothing else bounds a tile or a sentence from stretching
    /// across the pane.
    ///
    /// **444 is a reading measure**: about 75 characters of `HelmText.rowDetail`
    /// or 65 of `HelmText.rowTitle`, and the content width of the approved
    /// inspector drawing. As a maximum it only narrows a wider pane, so no
    /// control is reachable only on a big screen.
    ///
    /// Left-aligned at the call site, unlike `helmSettingsColumn`: a second
    /// column that centres its content leaves a gutter beside the master list,
    /// and the two columns read as drifting apart.
    public static let readingColumn: CGFloat = 444
}
