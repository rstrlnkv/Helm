import CoreGraphics

/// Whether the pane is wide enough for a master column and an inspector
/// beside it. Modelled on `DiskLayout` — a `private var` inside `body` is out
/// of a test's reach.
///
/// The master takes `.frame(minWidth: 240, idealWidth: 310, maxWidth: 310)`
/// and the inspector `.frame(minWidth: 260, maxWidth: .infinity)`, in an
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

    /// 560. `TheSplitThresholdFitsThePageItGatesTests` is what re-measures the
    /// floor this sits above; nothing here should be trusted as a number that
    /// stays true on its own.
    private static let masterAndInspector: CGFloat = 560

    /// Below this there is no inspector: one column at full width, and the
    /// description returns to the row, which is where it reads at a pane too
    /// narrow for a second column.
    var showsInspector: Bool { availableWidth >= Self.masterAndInspector }
}
