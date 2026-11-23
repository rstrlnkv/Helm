import CoreGraphics

/// The two badges a tile wears in the edit mode, as geometry only: a × at the art's top left (the app is moved to the Trash, after a question) and an eye
/// (`eye.slash`, the app is hidden) at its top right. **One function** (`frames`) places them, for the tile that draws them and for the hit test
/// (`LaunchpadHit.badge(at:in:)`) that lets a press on one reach its button instead of beginning a lift or a click. A folder wears none, and the new-app dot is not drawn while editing.
enum LaunchpadBadge {
    enum Kind: Equatable { case remove, hide }

    struct Kinds: OptionSet, Equatable {
        let rawValue: Int
        static let remove = Kinds(rawValue: 1)
        static let hide = Kinds(rawValue: 2)
    }

    struct Placed: Identifiable {
        let kind: Kind
        let frame: CGRect
        var id: Int { kind == .remove ? 0 : 1 }
    }

    /// The disc's side: a share of the icon, never under 20 pt (the icon already follows the scale).
    static func side(icon: CGFloat) -> CGFloat { max(20, icon * 0.28) }
    /// What a press may land on: the disc, and never under 24 pt.
    static func hit(icon: CGFloat) -> CGFloat { max(24, side(icon: icon)) }

    /// The press frames of `kinds` in a cell `cell` big, from the cell's top left: each centred on the art's corner (held inside the cell), `LaunchpadMetrics.newDotInset` of the icon in
    /// from the icon frame's corner (the icon frame is centred across the cell and `LaunchpadGeometry.iconTop` below its top, passed as `iconTop`), `hit(icon:)` square.
    static func frames(_ kinds: Kinds, cell: CGSize, icon: CGFloat, iconTop top: CGFloat) -> [Placed] {
        let inset = LaunchpadMetrics.newDotInset * icon, side = hit(icon: icon)
        let left = (cell.width - icon) / 2
        // Never out of the cell: on a small icon the press frame's 24 pt would reach over the row above, so it is held in (the disc moves with it).
        func box(_ x: CGFloat) -> CGRect {
            CGRect(x: min(max(0, x - side / 2), max(0, cell.width - side)), y: min(max(0, top + inset - side / 2), max(0, cell.height - side)), width: side, height: side)
        }
        var out: [Placed] = []
        if kinds.contains(.remove) { out.append(Placed(kind: .remove, frame: box(left + inset))) }
        if kinds.contains(.hide) { out.append(Placed(kind: .hide, frame: box(left + icon - inset))) }
        return out
    }
}
