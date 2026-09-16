import CoreGraphics
import HelmUI

/// Whether the pane is wide enough for a master column and an inspector
/// beside it. Modelled on `DiskLayout` — a `private var` inside `body` is out
/// of a test's reach.
///
/// The master takes `.frame(minWidth: 240, idealWidth: masterWidth, maxWidth:
/// masterWidth)` — 310 at this threshold, by `masterWidth`'s own floor — and the
/// inspector `.frame(minWidth: 260, maxWidth: .infinity)`, in an
/// `HStack(spacing: HelmSpace.s5)`, so on paper the floor is
/// 240 + 12 + 1 + 12 + 260 = 525 (master's minimum, two gaps, the divider,
/// the inspector's minimum). **Measured against the real page, and the paper
/// arithmetic was close but not the whole story**:
/// `TheSplitThresholdFitsThePageItGatesTests` mounts `HomebrewSettingsPage`
/// itself, substitutes the threshold and sweeps it — the inspector's action
/// first fits inside the pane at **521 pt**, a point under the paper floor,
/// because the master is a `List` that compresses under pressure and the
/// column squeezed first is the *inspector*, not the master. A probe of two
/// bare rectangles once measured 544 here; that probe is not in the tree, and
/// nothing about the shipping page matched it.
///
/// So the threshold carries slack over the measured floor, the way
/// `DiskLayout.ringAndList` carries slack over its own 645 pt measurement:
/// **560** — 39 pt above 521, re-measured by the same test on every run
/// rather than copied once here.
struct HomebrewSplit {
    let availableWidth: CGFloat

    /// **Whether the segmented switcher fitted the bar at this pane** — the
    /// second half of one boundary, and the reason this is a parameter rather
    /// than another number.
    ///
    /// The header's shape is `ViewThatFits`' answer and it moves with the
    /// language: swept a point at a time on the real page, 2026-09-16, the
    /// segmented bar first fits at en/zh/de below 400 · fr 466 · pt 482 ·
    /// es 554 · ru 566 · ja 572, against this file's own 560. So dragging a
    /// Russian window across 560…566 reorganised the page **twice in six
    /// points** — the columns collapsed, then the switcher became a menu — and
    /// Japanese did it across twelve. Neither change is wrong; two of them ten
    /// points apart is.
    ///
    /// `headerBar` folds this file's floor into the segmented candidate's own
    /// ideal width, so the one thing `ViewThatFits` answers is «is this pane
    /// wide enough for the whole wide page», and this reads that answer. The
    /// boundary is therefore `max(560, what the bar needs in this language)`,
    /// one width, in all eight.
    ///
    /// **Defaulted to `true`** so a caller asking only about width — the sweep
    /// in `TheSplitThresholdFitsThePageItGatesTests`, `HomebrewSplitTests` —
    /// still gets this type's own floor and nothing else.
    var segmentedHeaderFits: Bool = true

    /// 560. `TheSplitThresholdFitsThePageItGatesTests` is what re-measures the
    /// floor this sits above; nothing here should be trusted as a number that
    /// stays true on its own.
    ///
    /// Internal rather than private because `headerBar` needs the same number:
    /// it is the minimum width the wide page asks for, and the bar asks for it
    /// on the page's behalf. Read in exactly those two places.
    static let masterAndInspector: CGFloat = 560

    /// Below this there is no inspector: one column at full width, and the
    /// description returns to the row, which is where it reads at a pane too
    /// narrow for a second column.
    ///
    /// Both conditions, and the `&&` is not redundant belt: the header's answer
    /// already carries the floor, and this type still has to be able to answer
    /// for itself when nobody has asked the header.
    var showsInspector: Bool {
        segmentedHeaderFits && availableWidth >= Self.masterAndInspector
    }

    /// **How wide the master column is at this pane — a share of the slack
    /// rather than none of it.**
    ///
    /// It was `maxWidth: 310` at every width, and the result was backwards:
    /// measured 2026-09-16, a master row had 254 pt of content at the 984 pt
    /// pane the app draws and 484 at 540, where the pane is below the threshold
    /// above and the list has it to itself. So all three of this Mac's own
    /// `brew doctor` titles — 258.3, 546.9 and 327.8 pt — were truncated at the
    /// wide window and only one at the narrow one: **the wider the window, the
    /// less of the title a person saw**. Beside it the inspector was 649 pt
    /// wide and drew into 444 of them.
    ///
    /// The rule: the inspector keeps what it actually uses — its bounded
    /// reading column and the padding around it — and everything past that goes
    /// to the master, up to a ceiling of the same reading column. A column of
    /// package names is not prose and does not want the whole window; 444 is
    /// where a line stops being a line you scan.
    ///
    /// `310` is still the floor, and it is not arbitrary: it is what the column
    /// was, and `TheSplitThresholdFitsThePageItGatesTests` measured the 521 pt
    /// floor of the split layout against a master that width. At the threshold
    /// this answers 310 exactly, so that measurement still describes this page.
    var masterWidth: CGFloat {
        // The two gaps and the divider between the columns, as `managerBody`
        // spells them: `HStack(spacing: HelmSpace.s5)` either side of a
        // `Divider()`.
        let gutter = HelmSpace.s5 * 2 + 1
        // What the inspector needs before it starts wasting width:
        // `helmInspectorColumn`'s cap and the padding it pays around it.
        let inspector = HelmLayout.readingColumn + HelmSpace.s5 * 2
        let share = availableWidth - gutter - inspector
        return min(max(Self.masterFloor, share), HelmLayout.readingColumn)
    }

    /// 310 — the width the master column was at every pane, kept as the floor.
    private static let masterFloor: CGFloat = 310
}
