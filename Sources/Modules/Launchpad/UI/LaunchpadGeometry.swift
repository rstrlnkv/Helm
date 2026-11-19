import CoreGraphics
import HelmUI

/// Every size the window's layout depends on, worked out **once** from the screen's size when the window is built.
///
/// Nothing in the window measures: no `GeometryReader`, no preference, no size read back from a view. A layout that
/// asks the views how big they are and answers by changing them is a loop, and pass 3's page was one: the log showed the
/// system switching the keyboard tap off and memory up 559 MB. Here the size comes from the screen, the answer is a `let`, and
/// `TheLaunchpadWindowMeasuresNothingTests` fails when anything measures again; it is an optional test, run on request
/// (`bash Scripts/test.sh --filter TheLaunchpadWindowMeasuresNothingTests`).
struct LaunchpadGeometry: Equatable {
    /// The screen's size as used (the fallback when the real one was not a size): the window's root is exactly this.
    let size: CGSize
    let columns: Int
    let rows: Int
    /// Tiles on one page.
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

    /// A size that is not a size (zero, negative, not a number, infinite) is a 1280 × 800 screen.
    static let fallback = CGSize(width: 1280, height: 800)

    /// `topSafe` is the height of what the screen keeps at the top (a notch, the menu bar's room); the menu bar draws
    /// over the window's top strip (the window sits under it), so the grid starts below it.
    static func make(for size: CGSize, topSafe: CGFloat) -> LaunchpadGeometry {
        let usable = size.width.isFinite && size.height.isFinite && size.width >= 1 && size.height >= 1
        let screen = usable ? size : fallback
        let top = topSafe.isFinite ? max(0, min(topSafe, screen.height / 4)) : 0

        let usableWidth = screen.width * (1 - 2 * LaunchpadMetrics.sideMargin)
        let columns = max(3, min(8, Int(min(usableWidth / LaunchpadMetrics.tileMinimum, 1000))))
        let cellWidth = usableWidth / CGFloat(columns)

        let searchTop = top + LaunchpadMetrics.searchTop
        let gridTop = searchTop + LaunchpadMetrics.searchHeight + LaunchpadMetrics.gridGap
        let usableHeight = max(0, screen.height - gridTop - LaunchpadMetrics.dotsRoom)
        let rows = max(2, min(6, Int(min(usableHeight / LaunchpadMetrics.cellHeight, 1000))))

        return LaunchpadGeometry(
            size: screen, columns: columns, rows: rows, capacity: columns * rows,
            cellWidth: cellWidth, cellHeight: LaunchpadMetrics.cellHeight, icon: LaunchpadMetrics.windowIcon,
            pageWidth: screen.width, pageHeight: CGFloat(rows) * LaunchpadMetrics.cellHeight,
            gridTop: gridTop, dotsBottom: LaunchpadMetrics.dotsBottom, searchTop: searchTop)
    }

    /// Where slot `slot` of a page sits, from the page's top left: slots fill left to right from the grid's left edge, so a
    /// short last row stays on its columns.
    func origin(ofSlot slot: Int) -> CGPoint {
        CGPoint(x: (pageWidth - CGFloat(columns) * cellWidth) / 2 + CGFloat(slot % columns) * cellWidth,
                y: CGFloat(slot / columns) * cellHeight)
    }

    /// A folder's card, centred in the window: the title, then `rows` rows of `columns` cells, in the card's padding. One
    /// place for the card's drawing and for the lift's "outside the card".
    func card(columns: Int, rows: Int) -> CGRect {
        let width = CGFloat(columns) * cellWidth + 2 * Self.cardPadding
        let height = CGFloat(rows) * cellHeight + Self.cardTitle + Self.cardGap + 2 * Self.cardPadding
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    static let cardPadding = HelmSpace.s6
    static let cardGap = HelmSpace.s5
    /// The height the card gives its title (one line of the section heading).
    static let cardTitle: CGFloat = 22

    /// The middle of slot `slot`'s tile in the window's own coordinates.
    func center(ofSlot slot: Int) -> CGPoint {
        let o = origin(ofSlot: slot)
        return CGPoint(x: o.x + cellWidth / 2, y: gridTop + o.y + cellHeight / 2)
    }
}
