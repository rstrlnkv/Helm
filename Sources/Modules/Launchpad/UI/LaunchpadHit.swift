import CoreGraphics

/// What the grid holds, as far as a pointer's place needs it: the geometry, the shown page, how many tiles each page has
/// (the gap counted as one), and where the gap is. A **cell address** is `page * capacity + slot on the page`: it names a
/// place on a page, whatever the pages before it hold, so a page break or a short page moves nothing.
struct LaunchpadSurface: Equatable {
    let geometry: LaunchpadGeometry
    var page: Int
    var pageCounts: [Int]
    /// The address of the gap while a tile is lifted.
    var gap: Int?
    /// The addresses of the folder tiles a pointer held on opens (empty when the carried tile is itself a folder: they never nest).
    var folders: Set<Int> = []
    /// The open folder's card; the pointer's places are then the card's tiles, addressed by their index in it.
    var card: Card?

    var pageCount: Int { pageCounts.count }

    /// A folder's card as the window draws it (`LaunchpadGeometry.card`): `count` tiles in `columns` columns, as many rows as
    /// fit under the grid's height.
    struct Card: Equatable {
        let geometry: LaunchpadGeometry
        let count: Int
        let columns: Int
        let rows: Int
        let visibleRows: Int
        let rect: CGRect

        init(geometry: LaunchpadGeometry, count: Int) {
            self.geometry = geometry
            self.count = count
            columns = max(1, min(count, geometry.columns - 1))
            rows = (count + columns - 1) / columns
            visibleRows = max(1, min(rows, geometry.rows - 1))
            rect = geometry.card(columns: columns, rows: visibleRows)
        }

        /// More rows than the card shows: it scrolls, and the places below are not where a pointer's are.
        var scrolls: Bool { rows > visibleRows }

        /// Where the tiles begin: under the card's padding and title.
        var origin: CGPoint {
            CGPoint(x: rect.minX + LaunchpadGeometry.cardPadding,
                    y: rect.minY + LaunchpadGeometry.cardPadding + LaunchpadGeometry.cardTitle + LaunchpadGeometry.cardGap)
        }

        func center(ofSlot slot: Int) -> CGPoint {
            CGPoint(x: origin.x + (CGFloat(slot % columns) + 0.5) * geometry.cellWidth,
                    y: origin.y + (CGFloat(slot / columns) + 0.5) * geometry.cellHeight)
        }
    }
}

/// What is under the pointer. Pure: no view is asked.
enum LaunchpadHit: Equatable {
    /// A tile's cell. `core` is the middle of its icon (60% of the cell's width, the icon's height); the rest of the cell is its margin.
    case tile(address: Int, core: Bool)
    /// An empty cell of the grid, after the page's last tile.
    case gap(address: Int)
    /// The strip along the window's left (-1) or right (+1) side, as high as the grid.
    case edge(Int)
    /// Outside the open card and the margin around it (`LaunchpadLiftTiming.cardMargin`).
    case away
    case none

    static func at(_ point: CGPoint, in surface: LaunchpadSurface) -> LaunchpadHit {
        let g = surface.geometry
        guard point.x.isFinite, point.y.isFinite, g.cellWidth > 0, surface.pageCounts.indices.contains(surface.page) else { return .none }
        if let card = surface.card { return inCard(point, card) }
        let top = g.gridTop
        guard point.y >= top, point.y < top + CGFloat(g.rows) * g.cellHeight else { return .none }
        if point.x < LaunchpadLiftTiming.edgeWidth { return .edge(-1) }
        if point.x >= g.size.width - LaunchpadLiftTiming.edgeWidth { return .edge(1) }
        let x = point.x - g.origin(ofSlot: 0).x
        let y = point.y - top
        guard x >= 0, x < CGFloat(g.columns) * g.cellWidth else { return .none }
        let column = Int(x / g.cellWidth), row = Int(y / g.cellHeight)
        let slot = row * g.columns + column
        let address = surface.page * g.capacity + slot
        guard slot < surface.pageCounts[surface.page] else { return .gap(address: address) }
        let inX = x - CGFloat(column) * g.cellWidth, inY = y - CGFloat(row) * g.cellHeight
        let core = abs(inX - g.cellWidth / 2) <= g.cellWidth * 0.3 && inY >= LaunchpadMetrics.iconTop && inY < LaunchpadMetrics.iconTop + g.icon
        return .tile(address: address, core: core)
    }

    /// A card's tile (never a core: nothing is dropped onto an app in a folder), the empty cell after the last, or the card's
    /// own title and padding (`none`); outside it and its margin, `away`.
    private static func inCard(_ point: CGPoint, _ card: LaunchpadSurface.Card) -> LaunchpadHit {
        let margin = LaunchpadLiftTiming.cardMargin
        guard card.rect.insetBy(dx: -margin, dy: -margin).contains(point) else { return .away }
        let g = card.geometry
        let x = point.x - card.origin.x, y = point.y - card.origin.y
        guard x >= 0, y >= 0, x < CGFloat(card.columns) * g.cellWidth, y < CGFloat(card.visibleRows) * g.cellHeight else { return .none }
        let slot = Int(y / g.cellHeight) * card.columns + Int(x / g.cellWidth)
        return slot < card.count ? .tile(address: slot, core: false) : .gap(address: slot)
    }
}
