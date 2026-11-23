import CoreGraphics
import HelmUI

/// How wide the master column is beside the inspector. Modelled on `DiskLayout`:
/// a `private var` inside `body` is out of a test's reach.
///
/// There is no narrower layout: the narrowest pane the window gives is 1003 pt
/// (`DuplicatesLayout.swift`'s doc comment), so the two columns always fit. On
/// paper the least they need is 513: `masterMinimum`, the divider, the
/// inspector's 12 pt leading padding, `inspectorMinimum`; a probe that mounted
/// the page once read the inspector's action first fitting at 521 pt (not in
/// the tree, and nothing re-reads it).
struct HomebrewSplit {
    let availableWidth: CGFloat

    /// The least the master column and the inspector are laid out at beside each
    /// other: the pair the 521 pt reading was taken at.
    static let masterMinimum: CGFloat = 240
    static let inspectorMinimum: CGFloat = 260

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
    /// 12 pt of spacing after it; at 521 pt this answers 322, the same sum.
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
