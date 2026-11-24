import CoreGraphics
import HelmUI

/// How wide the master column is beside the inspector. Modelled on `DiskLayout`:
/// a `private var` inside `body` is out of a test's reach.
///
/// There is no narrower layout: the narrowest pane the window gives
/// (`DuplicatesLayout.swift`'s doc comment) is wider than the two columns need.
struct HomebrewSplit {
    let availableWidth: CGFloat

    /// The least the master column and the inspector are laid out at beside each
    /// other.
    static let masterMinimum: CGFloat = 240
    static let inspectorMinimum: CGFloat = 260

    /// **How wide the master column is at this pane: a share of the slack, plus the
    /// 12 pt the list side of the gutter does not spend.**
    ///
    /// The inspector keeps what it actually uses — its bounded reading column and
    /// the padding around it — and everything past that goes to the master, up to
    /// a ceiling of the same reading column. The 12 pt are added after the clamp,
    /// at floor and ceiling alike, so the divider stays where the share puts it.
    var masterWidth: CGFloat {
        // `HomebrewManager` spends nothing on the list's side of the gutter
        // (`HStack(spacing: 0)`).
        let gutter = HelmSpace.s5 * 2 + 1
        // What the inspector needs before it starts wasting width:
        // `helmInspectorColumn`'s cap and the padding it pays around it.
        let inspector = HelmLayout.readingColumn + HelmSpace.s5 * 2
        let share = availableWidth - gutter - inspector
        // The list-side gap, added after the clamp.
        return min(max(Self.masterFloor, share), HelmLayout.readingColumn) + HelmSpace.s5
    }

    /// The floor the *share* is clamped to before `masterWidth` adds the list
    /// side's 12 pt (so `masterWidth` answers 322 here).
    private static let masterFloor: CGFloat = 310
}
