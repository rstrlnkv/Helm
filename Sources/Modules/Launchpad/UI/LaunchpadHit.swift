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

    /// A folder's card as the window draws it (`LaunchpadGeometry.card`): `count` tiles in `columns` columns, `visibleRows` rows
    /// (the grid's less one) to a page, and `page` the one shown. A card of more tiles than a page holds has pages, and dots.
    struct Card: Equatable {
        let geometry: LaunchpadGeometry
        let count: Int
        let columns: Int
        let rows: Int
        let visibleRows: Int
        let rect: CGRect
        /// Tiles on one page of the card.
        let capacity: Int
        let pageCount: Int
        let page: Int

        init(geometry: LaunchpadGeometry, count: Int, page: Int = 0) {
            self.geometry = geometry
            self.count = count
            columns = max(1, min(count, geometry.columns - 1))
            rows = (count + columns - 1) / columns
            visibleRows = max(1, min(rows, geometry.rows - 1))
            capacity = columns * visibleRows
            pageCount = LaunchpadPaging.pageCount(items: count, capacity: capacity)
            self.page = LaunchpadPaging.clamped(page, count: pageCount)
            rect = geometry.card(columns: columns, rows: visibleRows, paged: pageCount > 1)
        }

        /// More tiles than a page holds: the card has pages, turned by swipe, wheel, dots and the lift's edge strips.
        var paged: Bool { pageCount > 1 }

        /// A page's width: the distance that is half a turn.
        var pageWidth: CGFloat { CGFloat(columns) * geometry.cellWidth }

        /// The page that holds the tile at `index` of the card's list.
        func page(ofIndex index: Int) -> Int { LaunchpadPaging.clamped(max(0, index) / capacity, count: pageCount) }

        /// The indices of the card's list that page `page` holds.
        func range(ofPage page: Int) -> Range<Int> {
            let from = min(count, max(0, page) * capacity)
            return from..<min(count, from + capacity)
        }

        /// Where the tiles begin: under the card's padding and title.
        var origin: CGPoint {
            CGPoint(x: rect.minX + LaunchpadGeometry.cardPadding,
                    y: rect.minY + LaunchpadGeometry.cardPadding + LaunchpadGeometry.cardTitle + LaunchpadGeometry.cardGap)
        }

        /// The middle of the tile at `slot` of the shown page (a slot of another page is read as its place on its own page).
        func center(ofSlot slot: Int) -> CGPoint {
            let place = slot % capacity
            return CGPoint(x: origin.x + (CGFloat(place % columns) + 0.5) * geometry.cellWidth,
                           y: origin.y + (CGFloat(place / columns) + 0.5) * geometry.cellHeight)
        }
    }
}

/// What is under the pointer. Pure: no view is asked.
enum LaunchpadHit: Equatable {
    /// A tile's cell. `core` is the middle of its icon (60% of the cell's width, the icon's height); the rest of the cell is its margin.
    case tile(address: Int, core: Bool)
    /// An empty cell of the grid, after the page's last tile.
    case gap(address: Int)
    /// The strip along the window's left (-1) or right (+1) side, as high as the grid; also the open paged card's side strips.
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
    /// own title and padding (`none`); outside it and its margin, `away`. A card with pages answers the strips left and right
    /// of its tiles (its padding and its margin) with `edge`, which turns its page. Addresses are the card's list's indices.
    private static func inCard(_ point: CGPoint, _ card: LaunchpadSurface.Card) -> LaunchpadHit {
        let margin = LaunchpadLiftTiming.cardMargin
        guard card.rect.insetBy(dx: -margin, dy: -margin).contains(point) else { return .away }
        let g = card.geometry
        let x = point.x - card.origin.x, y = point.y - card.origin.y
        if card.paged, x < 0 { return .edge(-1) }
        if card.paged, x >= card.pageWidth { return .edge(1) }
        guard x >= 0, y >= 0, x < card.pageWidth, y < CGFloat(card.visibleRows) * g.cellHeight else { return .none }
        let address = card.page * card.capacity + Int(y / g.cellHeight) * card.columns + Int(x / g.cellWidth)
        return address < card.count ? .tile(address: address, core: false) : .gap(address: address)
    }
}
