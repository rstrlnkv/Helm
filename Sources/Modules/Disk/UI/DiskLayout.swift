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
/// | bar: back, path, three controls         |  640 pt |
/// | bar with the scan statement as well     |  788 pt |
///
/// The settings window's pane (`SettingsWindow`, `ShellGeometry.cardFrame`)
/// fits the full bar; the layout still adapts to the width it is handed.
/// Nothing is dropped that there is room for, and what goes first is what costs
/// most for what it adds: the sentence about the measurement.
struct DiskLayout {
    let availableWidth: CGFloat

    /// 788 measured, plus the same slack.
    private static let barWithStatement: CGFloat = 800

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

    /// **A warning is not a thing to drop when the window is small**: behind
    /// `showsScanStatement` alone, a narrow pane would draw a stopped tree with
    /// nothing saying its figures are floors.
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
