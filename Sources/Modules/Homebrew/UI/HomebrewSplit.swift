import CoreGraphics

/// Whether the pane is wide enough for a master column and an inspector
/// beside it. Modelled on `DiskLayout` — a `private var` inside `body` is out
/// of a test's reach.
///
/// The master takes `.frame(minWidth: 240, idealWidth: 310, maxWidth: 310)`
/// and the inspector `.frame(minWidth: 260, maxWidth: .infinity)`, in an
/// `HStack(spacing: HelmSpace.s5)`, so on paper the floor is
/// 240 + 12 + 1 + 12 + 260 = 525 (master's minimum, two gaps, the divider,
/// the inspector's minimum). **Measured, and the arithmetic was wrong**: a
/// probe of that exact shape (two flexible rects and a `Divider()`, mounted
/// through `MountedRender` at widths from 480 to 834, reading the master's
/// own leading edge the way `HostsRowsFitTheMinimumPaneTests` does) found the
/// master still crawling into the gutter — leading edge at x = -1 — at 543 pt,
/// and flush at x = 0 only from **544 pt**. SwiftUI's own allocation for two
/// ranged children does not split the shortfall the way the sum-of-floors
/// arithmetic assumes.
///
/// So the threshold is the measured floor plus slack for a longer
/// localisation, the way `DiskLayout.ringAndList` carries slack over its own
/// 645 pt measurement: **560**.
struct HomebrewSplit {
    let availableWidth: CGFloat

    /// 544 pt measured (see above); the threshold carries slack over it.
    private static let masterAndInspector: CGFloat = 560

    /// Below this there is no inspector: one column at full width, and the
    /// description returns to the row, which is where it reads at a pane too
    /// narrow for a second column.
    var showsInspector: Bool { availableWidth >= Self.masterAndInspector }
}
