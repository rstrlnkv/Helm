import CoreGraphics

/// What fits, at the width there actually is.
///
/// The Disk result screen wants three things across one row of window: a ring,
/// a list, and a bar carrying a path, three controls and a sentence about the
/// measurement. Measured with the real font metrics rather than guessed at:
///
/// | piece                                   | needs   |
/// |-----------------------------------------|---------|
/// | ring column (300 pt frame + padding)    |  328 pt |
/// | list, comfortable for a long file name  |  316 pt |
/// | both side by side                       |  645 pt |
/// | bar: back, path, three controls         |  640 pt |
/// | bar with the scan statement as well     |  788 pt |
///
/// The settings window is 1100 pt wide by default and 1096 at its minimum
/// (`SettingsWindow`), and the card takes the window less the sidebar and a 4 pt
/// inset (`ShellGeometry.cardFrame`). At the default sidebar of 200 the detail
/// pane is 896 pt, or 892 at the minimum, and the full bar (788) fits in both;
/// a sidebar stored at its widest, 320 (`ShellGeometry.sidebarRange`), leaves
/// 776 and 772, **where it does not**.
///
/// Leaving the scan statement out of the bar for good would pay for the narrow
/// case with the wide one: on a large window the bar would hold a path on the
/// left, three controls on the right and a void between them.
///
/// So the layout adapts instead of compromising. Nothing is dropped that there
/// is room for, and what goes first is what costs most for what it adds: the
/// sentence before the ring, and the ring before the list — the list carries
/// every fact the ring does. The ring's step is not reached today: the narrowest
/// pane is wider than `showsRing` asks.
struct DiskLayout {
    let availableWidth: CGFloat

    /// 645 measured, plus slack for a longer localization of a row.
    private static let ringAndList: CGFloat = 660
    /// 788 measured, plus the same slack.
    private static let barWithStatement: CGFloat = 800

    /// Below this the ring goes and the list takes the whole pane. A 300 pt
    /// ring beside a squeezed list serves neither. The narrowest pane the
    /// window gives is 772 pt, so no window size reaches that branch today.
    var showsRing: Bool { availableWidth >= Self.ringAndList }

    /// The sentence about the measurement is the first thing to go: it is
    /// neither the path nor a control, and it is the widest item in the row.
    ///
    /// **This is the budget for the cosmetic sentence only.** The 788 pt it was
    /// measured for is the bar carrying «N files in M s», which is the widest of
    /// the three statements and the only one nobody needs — see `statement`.
    var showsScanStatement: Bool { availableWidth >= Self.barWithStatement }

    /// What the bar says about the tree beside it.
    ///
    /// Three sentences, and only one of them is decoration. `stopped` says every
    /// folder figure on the screen is a floor rather than a total; `measured`
    /// says the map is a memory and how old. `scanned` says how long the walk
    /// took, which changes nothing about what the numbers mean.
    enum ScanStatement: Equatable { case stopped, measured, scanned }

    /// **A warning is not a thing to drop when the window is small.** Behind
    /// `showsScanStatement` alone, all three sentences would go below 800 pt of
    /// pane — what a sidebar stored wider than 292 pt leaves in the minimum
    /// window, 772 at the widest — and a stopped tree would be drawn in full with
    /// nothing saying its figures are floors. The `stoppedHint` that explains it
    /// hangs on the same `Text`, so a screen reader would lose it too.
    ///
    /// Stopped comes first because it is the only one of the three that makes the
    /// sizes beside it untrue as totals.
    func statement(stopped: Bool, restored: Bool, hasResult: Bool) -> ScanStatement? {
        guard hasResult else { return nil }
        if stopped { return .stopped }
        if restored { return .measured }
        return showsScanStatement ? .scanned : nil
    }
}
