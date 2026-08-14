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
/// The settings window is 1060 pt wide by default and 860 at its minimum, and
/// the sidebar takes 250 of that — so the detail pane is 810 pt normally, where
/// the full bar (788) fits, and **610 at the minimum, where it does not**.
/// This paragraph reasoned from a 940 pt window until the Disk screen was the
/// reason the default grew — and then went on concluding that the full bar
/// never fits, which was the whole point of growing it.
///
/// The first attempt at this took the scan statement out of the bar
/// permanently, which paid for the narrow case with the wide one: on a large
/// window the bar then held a path on the left, three controls on the right
/// and a void between them, and the statement floated in the empty space
/// beside the ring.
///
/// So the layout adapts instead of compromising. Nothing is dropped that there
/// is room for, and what goes first is what costs most for what it adds: the
/// sentence before the ring, and the ring before the list — the list carries
/// every fact the ring does.
struct DiskLayout {
    let availableWidth: CGFloat

    /// 645 measured, plus slack for a longer localization of a row.
    private static let ringAndList: CGFloat = 660
    /// 788 measured, plus the same slack.
    private static let barWithStatement: CGFloat = 800

    /// Below this the ring goes and the list takes the whole pane. A 300 pt
    /// ring beside a squeezed list serves neither.
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

    /// **A warning is not a thing to drop when the window is small.** All three
    /// sentences used to sit behind `showsScanStatement`, so below 800 pt of pane
    /// — which is the pane the app opens at its own minimum, 610, and at the
    /// default window with the sidebar, 645 — a stopped tree was drawn in full
    /// with nothing saying its figures are floors, and yesterday's map was
    /// indistinguishable from one measured a second ago. The `stoppedHint` that
    /// explains it hangs on that same `Text`, so a screen reader lost it too.
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
