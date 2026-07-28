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
    var showsScanStatement: Bool { availableWidth >= Self.barWithStatement }
}
