import CoreGraphics
import HelmUI

/// Whether the pane is wide enough for a master column and an inspector
/// beside it. Modelled on `DiskLayout` — a `private var` inside `body` is out
/// of a test's reach.
///
/// The master takes `.frame(minWidth: 240, idealWidth: masterWidth, maxWidth:
/// masterWidth)` — 322 at this threshold, by `masterWidth`'s own floor — and
/// the inspector `.frame(minWidth: 260, maxWidth: .infinity)`, in an
/// `HStack(spacing: 0)` with the inspector's own `.padding(.leading,
/// HelmSpace.s5)` standing in for the stack's old spacing on that one side
/// (`TheGapBesideTheListClosesOnlyThereTests` — the list meets the divider
/// now, and only the inspector's side of the gutter still spends anything), so
/// on paper the floor is 240 + 1 + 12 + 260 = 513 (master's minimum, the
/// divider, the inspector's own padding, the inspector's minimum).
/// **Measured against the real page, and the paper arithmetic was close but
/// not the whole story**:
/// `TheSplitThresholdFitsThePageItGatesTests` mounts `HomebrewSettingsPage`
/// itself, substitutes the threshold and sweeps it — the inspector's action
/// first fits inside the pane at **521 pt**, close to but not the same claim
/// as the paper floor above: that number is a live measurement of a `List`
/// that compresses under pressure, where the column squeezed first is the
/// *inspector*, not the master, so nothing ties it to the minimum-width sum
/// in either direction. A probe of two bare rectangles once measured 544
/// here; that probe is not in the tree, and nothing about the shipping page
/// matched it. **That 521 pt reading predates the list-meets-divider fix and
/// was not retaken this pass** — what is checked instead, by
/// `TheMasterColumnTakesAShareOfAWidePaneTests.testMasterWidthIsTwelveAboveThePreFixFormulaEverywhere`,
/// is that `masterWidth` answers exactly 12 pt more than the formula it
/// replaced at every width: the list-side gap the fix closed is handed
/// straight to the master, unconditionally, while the stack spends exactly
/// 12 pt less getting past the divider (the same 12 pt, moved into the
/// inspector's own padding) — so the total width spent before the
/// inspector's own column starts is unchanged, and a reading taken against
/// it does not need to be retaken.
///
/// So the threshold carries slack over the measured floor, the way
/// `DiskLayout.ringAndList` carries slack over its own 645 pt measurement:
/// **560** — 39 pt above 521, re-measured by the same test on every run
/// rather than copied once here.
struct HomebrewSplit {
    let availableWidth: CGFloat

    /// 560. `TheSplitThresholdFitsThePageItGatesTests` is what re-measures the
    /// floor this sits above; nothing here should be trusted as a number that
    /// stays true on its own.
    ///
    /// It was also folded into the page's own header bar, whose width had to
    /// agree with it; the page's controls are in the window's toolbar now
    /// (`pageToolbar`) and this is the one boundary there is.
    static let masterAndInspector: CGFloat = 560

    /// Below this there is no inspector: one column at full width, and the
    /// description returns to the row, which is where it reads at a pane too
    /// narrow for a second column.
    var showsInspector: Bool {
        availableWidth >= Self.masterAndInspector
    }

    /// **Whether the list is the whole pane** — and therefore whether a press
    /// on a row replaces it with that row's own screen instead of moving the
    /// inspector beside it.
    ///
    /// The same fact as `showsInspector`, said the way the list needs to hear
    /// it. It is a property rather than a `!` at each call site because three
    /// separate things follow from it and they must not be able to disagree:
    /// the description comes back into the row, the chevron that promises the
    /// push is drawn, and the row gains the accessibility hint that says what
    /// the press does. A page that drew the chevron from its own `width < 560`
    /// would have two thresholds, and the one that moved would be the one
    /// nobody re-measured.
    var singleColumn: Bool { !showsInspector }

    /// **How wide the master column is at this pane — a share of the slack
    /// rather than none of it, plus the 12 pt the list-side gutter used to
    /// spend before the owner's second decision closed it.**
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
    /// reading column and the padding around it — and everything past that
    /// goes to the master, up to a ceiling of the same reading column — **and
    /// then the 12 pt the list-side gutter used to spend, added on top of that
    /// share at every width, floor and ceiling alike**, which is the owner's
    /// own second decision on the gap
    /// (`TheGapBesideTheListClosesOnlyThereTests`): the list grows into the
    /// gap it used to fall short of, and the divider and everything past it —
    /// the inspector included — stay exactly where the share alone would have
    /// put them. Handing the 12 pt only where the share already sat between
    /// its floor and its ceiling — which is what this property did the first
    /// time it closed the list-side gap — moved the divider by up to 12 pt at
    /// every other width, the 984 pt pane this page actually draws included;
    /// caught by a reviewer's probe of the formula rather than by any test in
    /// the tree, since the one guard mounting the real page
    /// (`TheGapBesideTheListClosesOnlyThereTests`) had picked the one width,
    /// 850 pt, where that first version and this one agree.
    ///
    /// `310` is still the floor the *share* is clamped to before the 12 pt is
    /// added, and it is not arbitrary: it is what the column was, and
    /// `TheSplitThresholdFitsThePageItGatesTests` measured the 521 pt floor of
    /// the split layout against a master that width, under the stack spacing
    /// this page no longer has. At the threshold this property now answers
    /// 322, not 310 — the same number the stack used to reach by spending its
    /// own 12 pt of spacing after a 310 pt master — so the divider sits where
    /// it always did and the 521 pt measurement still describes this page.
    var masterWidth: CGFloat {
        // The share is measured against the *old* two-sided budget — the
        // divider's position is not this decision's to move, only which side
        // of it pays for the gap that used to be visible. `managerBody` no
        // longer spends anything on the list's own side of the gutter
        // (`HStack(spacing: 0)`); what it used to spend there is handed to
        // the master unconditionally below, at the floor and the ceiling as
        // much as in between, so the divider — and the inspector beyond it —
        // never move (`TheGapBesideTheListClosesOnlyThereTests`).
        let gutter = HelmSpace.s5 * 2 + 1
        // What the inspector needs before it starts wasting width:
        // `helmInspectorColumn`'s cap and the padding it pays around it.
        let inspector = HelmLayout.readingColumn + HelmSpace.s5 * 2
        let share = availableWidth - gutter - inspector
        // The list-side gap the stack no longer spends, handed straight to
        // the master after the share is clamped — not before — so it lands
        // at the floor and the ceiling exactly as it does in between.
        return min(max(Self.masterFloor, share), HelmLayout.readingColumn) + HelmSpace.s5
    }

    /// 310 — the width the master column was at every pane before the
    /// share-based formula, kept as the floor the *share* is clamped to
    /// before `masterWidth` adds the list-side gutter's 12 pt back on top
    /// (which is why `masterWidth` itself answers 322 at this floor, not
    /// 310).
    private static let masterFloor: CGFloat = 310
}
