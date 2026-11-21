import CoreGraphics
import HelmUI

/// Every size the window's layout depends on, worked out from the screen's size and the grid settings when the window is built, and again only when the settings change
/// (`LaunchpadScreenState.regrid`).
///
/// Nothing in the window measures: no `GeometryReader`, no preference, no size read back from a view. A layout that
/// asks the views how big they are and answers by changing them is a loop, and pass 3's page was one: the log showed the
/// system switching the keyboard tap off and memory up 559 MB. Here the size comes from the screen, the answer is a pure value, and
/// `TheLaunchpadWindowMeasuresNothingTests` fails when anything measures again; it is an optional test, run on request
/// (`bash Scripts/test.sh --filter TheLaunchpadWindowMeasuresNothingTests`).
struct LaunchpadGeometry: Equatable {
    /// The screen's size as used (the fallback when the real one was not a size): the window's root is exactly this.
    let size: CGSize
    let columns: Int
    let rows: Int
    /// Cells on one page: a page holds fewer tiles when it has a large folder, which takes four.
    let capacity: Int
    let cellWidth: CGFloat
    let cellHeight: CGFloat
    let icon: CGFloat
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    /// From the window's top edge to the grid's.
    let gridTop: CGFloat
    /// From the window's bottom edge to the page dots'.
    let dotsBottom: CGFloat
    /// From the window's top edge to the search field's.
    let searchTop: CGFloat
    /// The top room as clamped, so a new grid for the same window is made from the same number.
    let topSafe: CGFloat

    /// A size that is not a size (zero, negative, not a number, infinite) is a 1280 × 800 screen.
    static let fallback = CGSize(width: 1280, height: 800)

    /// `topSafe` is the height of what the screen keeps at the top (a notch, the menu bar's room); the menu bar draws
    /// over the window's top strip (the window sits under it), so the grid starts below it. `settings` is the person's grid
    /// (`LaunchpadGridSettings`), clamped here again: whatever it holds, the result is a grid that fits the screen.
    static func make(for size: CGSize, topSafe: CGFloat, settings: LaunchpadGridSettings = .standard) -> LaunchpadGeometry {
        let usable = size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
        let screen = usable ? size : fallback
        let top = topSafe.isFinite ? max(0, min(topSafe, screen.height / 4)) : 0

        let usableWidth = screen.width * (1 - 2 * LaunchpadMetrics.sideMargin)
        let searchTop = top + LaunchpadMetrics.searchTop
        let gridStart = searchTop + LaunchpadMetrics.searchHeight + LaunchpadMetrics.gridGap
        let usableHeight = max(0, screen.height - gridStart - LaunchpadMetrics.dotsRoom)
        let (columns, rows) = counts(width: usableWidth, height: usableHeight, settings: settings)

        let cellWidth = usableWidth / CGFloat(columns)
        let icon = fit(want: CGFloat(settings.normalized().iconSize), cellWidth: cellWidth, rowHeight: usableHeight / CGFloat(rows))
        let cellHeight = LaunchpadMetrics.cellHeight(icon: icon)
        // The room the rows leave is shared above and below, so the grid hangs in the middle of what is under the search field.
        let gridTop = gridStart + max(0, usableHeight - CGFloat(rows) * cellHeight) / 2

        return LaunchpadGeometry(
            size: screen, columns: columns, rows: rows, capacity: columns * rows,
            cellWidth: cellWidth, cellHeight: cellHeight, icon: icon,
            pageWidth: screen.width, pageHeight: CGFloat(rows) * cellHeight,
            gridTop: gridTop, dotsBottom: LaunchpadMetrics.dotsBottom, searchTop: searchTop, topSafe: top)
    }

    /// How many columns and rows a grid of `width` by `height` has. Automatic: as many as hold the icon asked for (the
    /// narrowest a tile may be, the icon's own height), at most 8 and 6. Manual: the stored ones. Rows are then capped by the
    /// floor icon with its labels: a label does not shrink, so a short screen holds fewer rows than were asked for.
    static func counts(width: CGFloat, height: CGFloat, settings: LaunchpadGridSettings) -> (columns: Int, rows: Int) {
        let settings = settings.normalized()
        let want = CGFloat(settings.iconSize)
        var columns = settings.columns, rows = settings.rows
        if settings.automatic {
            let narrowest = max(LaunchpadMetrics.tileMinimum, want + 2 * LaunchpadMetrics.tileSidePadding)
            columns = max(3, min(8, Int(min(width / narrowest, 1000))))
            rows = max(2, min(6, Int(min(height / LaunchpadMetrics.cellHeight(icon: want), 1000))))
        }
        let holds = max(2, Int(min(height / LaunchpadMetrics.cellHeight(icon: LaunchpadMetrics.iconFloor), 1000)))
        return (columns, min(rows, holds))
    }

    /// The icon a cell draws: the one asked for, no bigger than the cell's width and height leave room for, no smaller
    /// than the floor. The asked size is a ceiling, never exceeded.
    static func fit(want: CGFloat, cellWidth: CGFloat, rowHeight: CGFloat) -> CGFloat {
        max(LaunchpadMetrics.iconFloor, min(want, cellWidth - 2 * LaunchpadMetrics.tileSidePadding, rowHeight - LaunchpadMetrics.cellChrome))
    }

    /// The grid for the category view: the same cells with an even number of columns (one fewer when odd), so a block, which is two
    /// columns wide, centres on the page and the spare column is left empty. Everything else is equal, `gridLeft` included by its own formula.
    var pairedColumns: LaunchpadGeometry {
        let even = max(2, columns - columns % 2)
        return LaunchpadGeometry(
            size: size, columns: even, rows: rows, capacity: even * rows, cellWidth: cellWidth, cellHeight: cellHeight, icon: icon,
            pageWidth: pageWidth, pageHeight: pageHeight, gridTop: gridTop, dotsBottom: dotsBottom, searchTop: searchTop, topSafe: topSafe)
    }

    /// Whether the window leaves the switch its room at the left of the search field: what is left between the side margin and
    /// the field is at least `LaunchpadMetrics.switchRoom`.
    var switchFits: Bool {
        (size.width - LaunchpadMetrics.searchWidth) / 2 - LaunchpadMetrics.sideMargin * size.width >= LaunchpadMetrics.switchRoom
    }

    /// The grid's left edge on a page.
    var gridLeft: CGFloat { (pageWidth - CGFloat(columns) * cellWidth) / 2 }

    /// Where a tile's cells sit, from the page's top left: cells fill left to right from the grid's left edge, so a short
    /// last row stays on its columns.
    func frame(of slot: LaunchpadPlacement.Slot) -> CGRect {
        CGRect(x: gridLeft + CGFloat(slot.column) * cellWidth, y: CGFloat(slot.row) * cellHeight,
               width: CGFloat(slot.span) * cellWidth, height: CGFloat(slot.span) * cellHeight)
    }

    /// The side of the icon a large folder draws: the block's width and height less what a tile holds besides its icon, so it
    /// is the small icon's room twice over.
    var largeMark: CGFloat {
        max(0, min(2 * cellWidth - 2 * LaunchpadMetrics.tileSidePadding, 2 * cellHeight - LaunchpadMetrics.cellChrome))
    }

    /// A folder's card, centred in the window: the title, then `rows` rows of `columns` cells, in the card's padding; `paged`
    /// adds a row of page dots under the cells. One place for the card's drawing and for the lift's "outside the card".
    func card(columns: Int, rows: Int, paged: Bool = false) -> CGRect {
        let width = CGFloat(columns) * cellWidth + 2 * Self.cardPadding
        let dots = paged ? Self.cardGap + Self.cardDots : 0
        let height = CGFloat(rows) * cellHeight + Self.cardTitle + Self.cardGap + 2 * Self.cardPadding + dots
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    static let cardPadding = HelmSpace.s6
    static let cardGap = HelmSpace.s5
    /// The height the card gives its title (one line of the section heading).
    static let cardTitle: CGFloat = 22
    /// The height of the card's row of page dots (the dots' own touch size).
    static let cardDots: CGFloat = 24

    /// The middle of a tile's cells in the window's own coordinates.
    func center(of slot: LaunchpadPlacement.Slot) -> CGPoint {
        let f = frame(of: slot)
        return CGPoint(x: f.midX, y: gridTop + f.midY)
    }
}
