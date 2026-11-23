import CoreGraphics

/// **Where each item of a page sits: the one function that turns a page's list into cells.**
///
/// A small tile fills one cell, a large folder a block of 2×2. Drawing, paging, the pointer's hit test, the lift's gap and the
/// arrow keys all take their cells from `place`, so none of them can disagree about where a block is.
///
/// First fit, in reading order from the page's start: a block takes the first place where four cells are free, so the
/// small tiles after it fill the strip it skipped; the stored order is not changed, only where it lands. The page ends at the
/// first item that does not fit; it and everything after it go to the next page, so a page is always a run of the stored order
/// and the first item of a page always fits.
enum LaunchpadPlacement {
    /// A tile's cells: its top left cell and the cells a side it covers (1, or 2 for a large folder).
    struct Slot: Equatable {
        let column: Int
        let row: Int
        let span: Int

        func covers(column c: Int, row r: Int) -> Bool {
            c >= column && c < column + span && r >= row && r < row + span
        }
    }

    /// The slots of the longest prefix of `large` (one flag per item) a page of `columns` by `rows` holds, in item order. A
    /// grid under 2 a side has no room for a block, so every item is one cell; a grid with no cell holds nothing.
    static func place(_ large: [Bool], columns: Int, rows: Int) -> [Slot] {
        guard columns > 0, rows > 0 else { return [] }
        var taken = [Bool](repeating: false, count: columns * rows)
        var firstFree = 0
        var slots: [Slot] = []
        for isLarge in large {
            let span = isLarge && columns >= 2 && rows >= 2 ? 2 : 1
            guard let at = firstFit(span, from: firstFree, taken: taken, columns: columns, rows: rows) else { break }
            for r in at.row..<at.row + span { for c in at.column..<at.column + span { taken[r * columns + c] = true } }
            while firstFree < taken.count, taken[firstFree] { firstFree += 1 }
            slots.append(Slot(column: at.column, row: at.row, span: span))
        }
        return slots
    }

    private static func firstFit(_ span: Int, from start: Int, taken: [Bool], columns: Int, rows: Int) -> (column: Int, row: Int)? {
        var cell = start
        while cell < taken.count {
            let c = cell % columns, r = cell / columns
            if c <= columns - span, r <= rows - span, !taken[cell],
               (0..<span).allSatisfy({ dr in (0..<span).allSatisfy { dc in !taken[(r + dr) * columns + c + dc] } }) {
                return (c, r)
            }
            cell += 1
        }
        return nil
    }

    /// The item an Up (`dy` -1) or Down (+1) key reaches from item `item`: the one that covers the cell above its top row or
    /// below its bottom row, in the item's own left column; nil when there is none (the selection stays).
    static func vertical(from item: Int, dy: Int, in slots: [Slot]) -> Int? {
        guard slots.indices.contains(item), dy != 0 else { return nil }
        let s = slots[item]
        let row = dy < 0 ? s.row - 1 : s.row + s.span
        return slots.firstIndex { $0.covers(column: s.column, row: row) }
    }
}
