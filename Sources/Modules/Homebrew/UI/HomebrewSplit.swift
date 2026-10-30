import CoreGraphics
import HelmUI

/// Whether the pane is wide enough for a master column and an inspector beside
/// it. Modelled on `DiskLayout`: a `private var` inside `body` is out of a test's reach.
///
/// On paper the floor is 513: `masterMinimum`, the divider, the inspector's 12 pt
/// leading padding, `inspectorMinimum`. A probe that mounted the page read the
/// inspector's action first fitting at 521 pt. That probe is not in the tree and
/// nothing re-reads the number: it describes the page as it then stood, and the
/// list-meets-divider change moved 12 pt from the stack to the master, which
/// leaves the total the same by arithmetic, not by a reading.
///
/// So **560** carries slack over 521, as `DiskLayout.ringAndList` does over its
/// own measurement.
struct HomebrewSplit {
    let availableWidth: CGFloat

    /// 560: above the 521 pt reading (the type's doc). This is the one boundary.
    static let masterAndInspector: CGFloat = 560

    /// The least the master column and the inspector are laid out at beside each
    /// other: the pair the 521 pt reading was taken at.
    static let masterMinimum: CGFloat = 240
    static let inspectorMinimum: CGFloat = 260

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

    /// **How wide the master column is at this pane: a share of the slack, plus the
    /// 12 pt the list side of the gutter does not spend.**
    ///
    /// A fixed `maxWidth: 310` at every width was backwards: a master row had 254 pt
    /// of content at the 984 pt pane the app draws and 484 at 540, where the list has
    /// the pane to itself (read once by hand, no guard), so a `brew doctor` title
    /// was cut more the wider the window.
    ///
    /// The rule: the inspector keeps what it actually uses — its bounded reading
    /// column and the padding around it — and everything past that goes to the
    /// master, up to a ceiling of the same reading column. The 12 pt are added on
    /// top of that share at every width, floor and ceiling alike, so the divider
    /// and everything past it stay where the share alone would put them. Handing
    /// them over only where the share sat between its floor and its ceiling would
    /// move the divider by up to 12 pt at every other width; at 850 pt both agree,
    /// so a check at that width alone cannot see it.
    ///
    /// `310` is the floor the *share* is clamped to before the 12 pt is added. The
    /// 521 reading was taken against a master of that width, with the stack's own
    /// 12 pt of spacing after it; at the threshold this answers 322, the same sum.
    var masterWidth: CGFloat {
        // The divider does not move: the gap is the master's.
        // `HomebrewManager` spends nothing on the list's own side of the
        // gutter (`HStack(spacing: 0)`); the 12 pt it would have spent go to
        // the master below, at the floor and the ceiling as much as in between.
        let gutter = HelmSpace.s5 * 2 + 1
        // What the inspector needs before it starts wasting width:
        // `helmInspectorColumn`'s cap and the padding it pays around it.
        let inspector = HelmLayout.readingColumn + HelmSpace.s5 * 2
        let share = availableWidth - gutter - inspector
        // The list-side gap the stack does not spend, handed straight to
        // the master after the share is clamped — not before — so it lands
        // at the floor and the ceiling exactly as it does in between.
        return min(max(Self.masterFloor, share), HelmLayout.readingColumn) + HelmSpace.s5
    }

    /// 310: the floor the *share* is clamped to before `masterWidth` adds the
    /// list side's 12 pt back on top (which is why `masterWidth` answers 322 at
    /// this floor, not 310).
    private static let masterFloor: CGFloat = 310
}
