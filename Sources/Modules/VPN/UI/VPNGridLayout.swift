// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

/// How many columns the connection cards get, and how many of them are drawn
/// before a person asks for the rest.
///
/// **The column count is arithmetic, not a width.** `.adaptive(minimum:)` picks
/// the count from the pane and got it wrong in the other direction — two
/// connections were laid out in three columns and used two, leaving 233 pt of
/// nothing beside them. Counting instead fixed that pair and broke everything
/// from four on: `min(count, 3)` drew 3+1 at four connections, with **477 pt**
/// of empty row beside the last card, and 3+3+2 at eight.
///
/// So the rule is stated as what it is protecting: **the fewest rows among the
/// column counts that leave at most one empty slot.** One empty slot at the end
/// of a row reads as a list that finished; two reads as a layout that failed,
/// which is what the photograph of four connections showed. A fourth column is
/// not offered — 167 pt at the settings column, under the 190 pt minimum the
/// card has always declared, and too narrow for a name beside a verb.
///
/// The count is asked of the **total**, never of what is on screen, so pressing
/// «Show all» adds rows to the grid rather than re-sizing the cards already in
/// it. `TheGridLeavesNoHoleTests` holds all of this.
enum VPNGridLayout {
    /// See the note above: a third column takes the width the row card spends
    /// on the configuration's name.
    static let maxColumns = 2

    /// How many cards are drawn before «Show all».
    ///
    /// Six, and not five or seven, because it is divisible by every column
    /// count this file can return — so the collapsed grid is a full rectangle
    /// whatever the total is, and the state a person sees without pressing
    /// anything never has the hole in it.
    static let collapsedLimit = 6

    /// One empty slot is a row that ended. Two is a gap.
    private static let tolerableHole = 1

    /// Empty slots in the last row.
    static func hole(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let remainder = count % columns
        return remainder == 0 ? 0 : columns - remainder
    }

    static func columns(for count: Int) -> Int {
        guard count > 1 else { return 1 }
        let candidates = (1...min(maxColumns, count))
            .filter { hole(count: count, columns: $0) <= tolerableHole }
        // Never empty: one column leaves no hole at any count, so the filter
        // cannot starve the choice — it can only make a tall arrangement the
        // last resort, which is what `rows` then rules out.
        return candidates.min { rows(count, in: $0) < rows(count, in: $1) } ?? maxColumns
    }

    /// How many cards are on screen at this count in this state.
    static func shown(_ count: Int, expanded: Bool) -> Int {
        expanded ? count : min(count, collapsedLimit)
    }

    private static func rows(_ count: Int, in columns: Int) -> Int {
        (count + columns - 1) / columns
    }
}
