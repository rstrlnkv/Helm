import CoreGraphics

/// What fits in the duplicates toolbar, at the width there actually is.
///
/// The row wants four things: the folder it searched, how much it found, and
/// two controls. Measured with the real font metrics in the widest of the eight
/// languages (`Scripts/layout/measure-duplicates-bar.swift`):
///
/// | piece                                        | needs   |
/// |----------------------------------------------|---------|
/// | both controls                                |  266 pt |
/// | the count line                               |  192 pt |
/// | path floor + controls + chrome               |  538 pt |
/// | the same with the count                      |  738 pt |
///
/// The path is the piece that truncates, but only down to a floor: `/…re` is
/// not a location, and a path that says nothing costs the row its whole point.
/// So below the width that holds everything, the count goes first — it repeats
/// what the list beneath it already shows, group by group, while the path and
/// the controls appear nowhere else.
struct DuplicatesLayout {
    let availableWidth: CGFloat

    /// 738 measured, plus slack for a longer number.
    private static let barWithCount: CGFloat = 760

    var showsCount: Bool { availableWidth >= Self.barWithCount }
}
