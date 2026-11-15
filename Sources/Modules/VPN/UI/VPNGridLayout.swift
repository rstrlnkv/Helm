// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import CoreGraphics
import HelmUI

/// How many columns the connection cards get, how wide a card may be, and how
/// many of them are drawn before a person asks for the rest.
///
/// **The column count is arithmetic, not a width.** A count taken from the pane
/// leaves columns empty on a Mac with two connections; one taken from the count
/// alone makes a card the size of a paragraph of one. So: one connection is one
/// column, two or more are two (`maxColumns`). A third column would leave a card
/// too narrow for a name beside a verb, a fourth would be under `cardMinimum` at
/// the settings column. With two columns an odd total leaves exactly one empty
/// slot at the end, which reads as a list that finished.
///
/// The count is asked of the **total**, never of what is on screen, so pressing
/// «Show all» adds rows to the grid rather than re-sizing the cards already in
/// it.
enum VPNGridLayout {
    /// See the note above.
    static let maxColumns = 2

    /// The narrowest a card is drawn.
    static let cardMinimum: CGFloat = 190

    /// The widest a connection card may grow: **half the row**, less the gap
    /// beside it. Derived rather than typed, so it stays true if the settings
    /// column moves. One connection gets a half-row card instead of a banner
    /// across the page; two fill the row exactly and finish level with the card
    /// below.
    static var cardCeiling: CGFloat { (HelmLayout.cardWidth - HelmSpace.s5) / 2 }

    /// How many cards are drawn before «Show all».
    ///
    /// Six, and not five or seven, because it is divisible by every column
    /// count this file can return, so the grid a person sees cut off by "Show
    /// all" is a full rectangle.
    static let collapsedLimit = 6

    static func columns(for count: Int) -> Int {
        min(max(count, 1), maxColumns)
    }

    /// How many cards are on screen at this count in this state.
    static func shown(_ count: Int, expanded: Bool) -> Int {
        expanded ? count : min(count, collapsedLimit)
    }
}
