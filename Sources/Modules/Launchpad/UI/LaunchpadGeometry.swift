import CoreGraphics
import HelmUI
import HelmRuntime

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
    /// The grid asked for, as `make` read it: what `pairedColumns` makes the category view's grid from again. Rows and columns are
    /// the standard ones while it is automatic, which ignores them, so two grids that differ in nothing drawn are equal.
    let asked: LaunchpadGridSettings
    /// Whether an app's name is drawn (`LaunchpadGridSettings.showNames`): a cell is one line shorter without.
    var names: Bool { asked.showNames }
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
    /// What the layout's gaps, padding, label and icon follow: the screen's `LaunchpadMetrics.scale(for:topSafe:)` times the person's multiplier under Automatic, 1 under Manual.
    /// The search field, the tabs and the card's title and dots keep their size; their places follow it.
    let scale: CGFloat
    /// From the window's side to the grid's left edge: where the tabs begin, so the header and the grid share an edge on every screen.
    let sideInset: CGFloat

    /// What a tile holds besides its icon, from a cell's top to its icon's top, and the side padding the fit counts: `LaunchpadMetrics`' figures at `scale`.
    var chrome: CGFloat { LaunchpadMetrics.cellChrome(names: names, scale: scale) }
    var iconTop: CGFloat { HelmSpace.s3 * scale }
    var tilePadding: CGFloat { HelmSpace.s2 * scale }
    /// A page dot and its touch size: larger on a screen that scales up, never smaller.
    var dotSize: CGFloat { 8 * max(1, scale) }
    var dotHit: CGFloat { 24 * max(1, scale) }

    /// Kept under the grid for the page dots: `LaunchpadMetrics.dotsRoom` at `scale`, and never less than the dots' bottom offset and their touch size, which does
    /// not shrink with the scale, so the last row never reaches the touch area on a small scale.
    var dotsRoom: CGFloat { Self.dotsRoom(scale: scale) }
    static func dotsRoom(scale: CGFloat) -> CGFloat {
        max(LaunchpadMetrics.dotsRoom * scale, LaunchpadMetrics.dotsBottom * scale + 24 * max(1, scale))
    }

    /// A size that is not a size (zero, negative, not a number, infinite) is a 1280 × 800 screen.
    static let fallback = CGSize(width: 1280, height: 800)

    /// `topSafe` is the height of what the screen keeps at the top (a notch, the menu bar's room); the menu bar draws
    /// over the window's top strip (the window sits under it), so the grid starts below it. `settings` is the person's grid
    /// (`LaunchpadGridSettings`), clamped here again: whatever it holds, the result is a grid that fits the screen.
    static func make(for size: CGSize, topSafe: CGFloat, settings: LaunchpadGridSettings = .standard) -> LaunchpadGeometry {
        let usable = size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
        let screen = usable ? size : fallback
        let top = topSafe.isFinite ? max(0, min(topSafe, screen.height / 4)) : 0

        var asked = settings.normalized()
        let automatic = asked.automatic
        let scale = automatic ? automaticScale(base: LaunchpadMetrics.scale(for: screen, topSafe: top), multiplier: CGFloat(asked.sizeMultiplier),
                                               screen: screen, top: top) : 1
        let usableWidth = screen.width * (1 - 2 * LaunchpadMetrics.sideMargin)
        let searchTop = top + LaunchpadMetrics.searchTop * scale
        let gridStart = searchTop + LaunchpadMetrics.searchHeight + LaunchpadMetrics.gridGap * scale
        let usableHeight = max(0, screen.height - gridStart - dotsRoom(scale: scale))
        let (columns, rows) = counts(width: usableWidth, height: usableHeight, settings: asked, scale: scale)

        let names = asked.showNames
        // The ask is what is drawn from: Automatic's rows, columns and points are the standard ones, which it ignores, and Manual has no multiplier
        // (`scale` already holds it under Automatic), so two grids that differ in nothing drawn are equal and a changed hidden value regrids nothing.
        let want: CGFloat
        if automatic {
            want = (CGFloat(LaunchpadMetrics.windowIcon) * scale).rounded(.down).clamped(to: 0...LaunchpadMetrics.automaticIconCeiling)
            asked.rows = LaunchpadGridSettings.standard.rows; asked.columns = LaunchpadGridSettings.standard.columns; asked.iconSize = LaunchpadGridSettings.standard.iconSize
        } else {
            want = CGFloat(asked.iconSize)
            asked.sizeMultiplier = LaunchpadGridSettings.standard.sizeMultiplier
        }
        let cellWidth = automatic ? min(usableWidth / CGFloat(columns), LaunchpadMetrics.cellWidthCap * scale) : usableWidth / CGFloat(columns)
        let icon = fit(want: want, cellWidth: cellWidth, rowHeight: usableHeight / CGFloat(rows), names: names, scale: scale)
        let cellHeight = LaunchpadMetrics.cellHeight(icon: icon, names: names, scale: scale)
        // The room the rows leave is shared above and below, so the grid hangs in the middle of what is under the search field.
        let gridTop = gridStart + max(0, usableHeight - CGFloat(rows) * cellHeight) / 2

        return LaunchpadGeometry(
            size: screen, columns: columns, rows: rows, capacity: columns * rows,
            cellWidth: cellWidth, cellHeight: cellHeight, icon: icon, asked: asked,
            pageWidth: screen.width, pageHeight: CGFloat(rows) * cellHeight,
            gridTop: gridTop, dotsBottom: LaunchpadMetrics.dotsBottom * scale, searchTop: searchTop, topSafe: top,
            scale: scale, sideInset: (screen.width - CGFloat(columns) * cellWidth) / 2)
    }

    /// The scale Automatic draws at: the screen's `base` times the person's `multiplier`, and where that makes the seven columns and five rows too big for the screen, the largest
    /// scale between `base` and it that they fit at, never less than `base`; it is worked out with app names on (the taller cell), so the scale does not depend on `showNames` and the category view, which keeps names, draws at the scale of the grid it comes from. Everything follows the scale (icon, label, padding, the room above and below the grid), so a multiplier
    /// above 1 that was not held would grow the chrome faster than the room left and give a smaller icon than ×1. Below 1 nothing needs holding: smaller always fits.
    static func automaticScale(base: CGFloat, multiplier: CGFloat, screen: CGSize, top: CGFloat) -> CGFloat {
        let wanted = base * multiplier
        guard wanted > base else { return wanted }
        let usableWidth = screen.width * (1 - 2 * LaunchpadMetrics.sideMargin)
        func fits(_ scale: CGFloat) -> Bool {
            let icon = (CGFloat(LaunchpadMetrics.windowIcon) * scale).rounded(.down)
            let start = top + LaunchpadMetrics.searchTop * scale + LaunchpadMetrics.searchHeight + LaunchpadMetrics.gridGap * scale
            let rows = CGFloat(LaunchpadMetrics.automaticRows) * LaunchpadMetrics.cellHeight(icon: icon, names: true, scale: scale)
            let cell = min(usableWidth / CGFloat(LaunchpadMetrics.automaticColumns), LaunchpadMetrics.cellWidthCap * scale)
            return rows <= screen.height - start - dotsRoom(scale: scale) && icon <= cell - 2 * HelmSpace.s2 * scale
        }
        guard fits(base) else { return base }
        if fits(wanted) { return wanted }
        var low = base, high = wanted
        for _ in 0..<30 {
            let mid = (low + high) / 2
            if fits(mid) { low = mid } else { high = mid }
        }
        return low
    }

    /// How many columns and rows a grid of `width` by `height` has. Automatic: seven and five on every screen, fewer only where the screen cannot hold them
    /// (columns that cannot hold the floor icon, rows that the floor icon with its labels leaves no room for). Manual: the stored ones. Rows are then capped
    /// by the floor icon with its labels: a label does not shrink, so a short screen holds fewer rows than were asked for.
    static func counts(width: CGFloat, height: CGFloat, settings: LaunchpadGridSettings, scale: CGFloat) -> (columns: Int, rows: Int) {
        let settings = settings.normalized()
        var columns = settings.columns, rows = settings.rows
        if settings.automatic {
            let narrowest = LaunchpadMetrics.iconFloor + 2 * HelmSpace.s2 * scale
            columns = max(3, min(LaunchpadMetrics.automaticColumns, Int(min(width / narrowest, 1000))))
            rows = LaunchpadMetrics.automaticRows
        }
        let holds = max(2, Int(min(height / LaunchpadMetrics.cellHeight(icon: LaunchpadMetrics.iconFloor, names: settings.showNames, scale: scale), 1000)))
        return (columns, min(rows, holds))
    }

    /// The icon a cell draws: the one asked for, no bigger than the cell's width and height leave room for, no smaller
    /// than the floor. The asked size is a ceiling, never exceeded.
    static func fit(want: CGFloat, cellWidth: CGFloat, rowHeight: CGFloat, names: Bool, scale: CGFloat) -> CGFloat {
        max(LaunchpadMetrics.iconFloor, min(want, cellWidth - 2 * HelmSpace.s2 * scale, rowHeight - LaunchpadMetrics.cellChrome(names: names, scale: scale)))
    }

    /// The grid for the category view: the grid made again with names on, with an even number of columns (one fewer when odd), so a block, which is two
    /// columns wide, centres on the page and the spare column is left empty. **It keeps the two lines of label even with app names off**:
    /// its blocks keep their names, so its cells, rows and large marks are the grid's with names on, not the shorter ones.
    var pairedColumns: LaunchpadGeometry {
        var named = asked
        named.showNames = true
        let base = names ? self : Self.make(for: size, topSafe: topSafe, settings: named)
        let even = max(2, base.columns - base.columns % 2)
        return LaunchpadGeometry(
            size: size, columns: even, rows: base.rows, capacity: even * base.rows, cellWidth: base.cellWidth, cellHeight: base.cellHeight, icon: base.icon,
            asked: base.asked, pageWidth: pageWidth, pageHeight: base.pageHeight, gridTop: base.gridTop, dotsBottom: dotsBottom, searchTop: searchTop, topSafe: topSafe,
            scale: scale, sideInset: (size.width - CGFloat(even) * base.cellWidth) / 2)
    }

    /// Whether the window leaves the switch its room at the left of the search field: what is left between the side margin and
    /// the field is at least `LaunchpadMetrics.switchRoom`.
    var switchFits: Bool {
        (size.width - LaunchpadMetrics.searchWidth) / 2 - sideInset >= LaunchpadMetrics.switchRoom
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
        max(0, min(2 * cellWidth - 2 * tilePadding, 2 * cellHeight - chrome))
    }

    /// A folder's card, centred in the window: the title, then `rows` rows of `columns` cells, in the card's padding; `paged`
    /// adds a row of page dots under the cells. One place for the card's drawing and for the lift's "outside the card".
    func card(columns: Int, rows: Int, paged: Bool = false) -> CGRect {
        let width = CGFloat(columns) * cellWidth + 2 * cardPadding
        let dots = paged ? cardGap + Self.cardDots : 0
        let height = CGFloat(rows) * cellHeight + Self.cardTitle + cardGap + 2 * cardPadding + dots
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    /// The card's padding and the gap between its parts follow the scale; its title and its row of dots keep their size.
    var cardPadding: CGFloat { HelmSpace.s6 * scale }
    var cardGap: CGFloat { HelmSpace.s5 * scale }
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
