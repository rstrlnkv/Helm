// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Helm

import SwiftUI

public extension View {
    /// **A line of a hero: centred on its column, and allowed the second line it
    /// needs.**
    ///
    /// Both of this app's heroes set their state as a *sentence* at 40 pt rather
    /// than as a figure, and a sentence that long wraps in most languages at
    /// most window widths — Keep Awake's idle sentence needs 407 pt in English
    /// and 742 in German against a header column of 684. A `Text` with neither
    /// of these two is drawn flush left: Keep Awake photographed its German
    /// headline on centres **147.75 pt apart** while every ink check on that
    /// page stayed green, because summed over a band a ragged pair of lines is
    /// exactly as many pixels as a centred one.
    ///
    /// The pair, never either half — measured on that string in that column:
    /// 147.75 pt apart with neither, 0.25 with both.
    ///
    /// **The size is deliberately not here.** The three slots that take this do
    /// not share one — 40 pt light for the figure, `HelmText.rowTitle` for the
    /// caption under it, and a countdown that adds tabular digits and negative
    /// tracking of its own. What they share is how a line behaves when it wraps,
    /// and that is all this carries.
    ///
    /// A file of its own rather than a member of `HelmSurfaces`, which is
    /// already past this repository's own length rule and is where the page
    /// header and its hover light live.
    func helmHeroSentence() -> some View {
        multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
