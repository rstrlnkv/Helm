import XCTest
@testable import Module_Launchpad_UI

/// The pointer's reading of a page with a block: every point of the 2×2 block is its core (nothing beside it moves the gap by
/// hovering it), a cell no tile covers is the gap at the end of the page, and a small tile's core is as it was before blocks.
final class ALargeFolderIsCoreAllOverAndASmallTileKeepsItsMarginsTests: XCTestCase {
    private let g = LaunchpadGeometry.make(for: CGSize(width: 1920, height: 1080), topSafe: 0)
    private typealias Slot = LaunchpadPlacement.Slot

    /// Item 0 small at (0,0), item 1 the block at (1,0), item 2 small at (3,0), item 3 small at (0,1); the rest of row 1 is empty.
    private var surface: LaunchpadSurface {
        LaunchpadSurface(geometry: g, page: 0,
                         slots: [[Slot(column: 0, row: 0, span: 1), Slot(column: 1, row: 0, span: 2), Slot(column: 3, row: 0, span: 1), Slot(column: 0, row: 1, span: 1)]],
                         gap: nil, folders: [1])
    }

    private func point(column: CGFloat, row: CGFloat, dx: CGFloat = 0, dy: CGFloat = 0) -> CGPoint {
        CGPoint(x: g.gridLeft + column * g.cellWidth + dx, y: g.gridTop + row * g.cellHeight + dy)
    }

    func testEveryPointOfTheBlockIsItsCore() {
        XCTAssertGreaterThanOrEqual(g.columns, 4)
        var seen = 0
        for dx in stride(from: 0.5, to: 2 * g.cellWidth, by: g.cellWidth / 7) {
            for dy in stride(from: 0.5, to: 2 * g.cellHeight, by: g.cellHeight / 7) {
                XCTAssertEqual(LaunchpadHit.at(point(column: 1, row: 0, dx: dx, dy: dy), in: surface), .tile(address: 1, core: true), "\(dx),\(dy)")
                seen += 1
            }
        }
        XCTAssertGreaterThan(seen, 100, "subject: the block was swept")
        for corner in [point(column: 1, row: 0, dx: 0.01, dy: 0.01), point(column: 3, row: 2, dx: -0.01, dy: -0.01)] {
            XCTAssertEqual(LaunchpadHit.at(corner, in: surface), .tile(address: 1, core: true))
        }
        // One step outside the block is not the block.
        XCTAssertNotEqual(LaunchpadHit.at(point(column: 3, row: 1, dx: 5, dy: 5), in: surface), .tile(address: 1, core: true))
        XCTAssertNotEqual(LaunchpadHit.at(point(column: 1, row: 2, dx: 5, dy: 5), in: surface), .tile(address: 1, core: true))
    }

    func testASmallTilesCoreAndMarginAreUnchanged() {
        let w = g.cellWidth
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 0, dx: w / 2, dy: LaunchpadMetrics.iconTop + g.icon / 2), in: surface), .tile(address: 0, core: true))
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 0, dx: w / 2 + w * 0.29, dy: LaunchpadMetrics.iconTop + 2), in: surface), .tile(address: 0, core: true))
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 0, dx: w / 2 + w * 0.32, dy: LaunchpadMetrics.iconTop + 2), in: surface), .tile(address: 0, core: false))
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 0, dx: w / 2 - w * 0.32, dy: LaunchpadMetrics.iconTop + 2), in: surface), .tile(address: 0, core: false))
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 0, dx: w / 2, dy: LaunchpadMetrics.iconTop - 2), in: surface), .tile(address: 0, core: false))
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 0, dx: w / 2, dy: LaunchpadMetrics.iconTop + g.icon + 2), in: surface), .tile(address: 0, core: false))
        // The tile that stands after the block is item 2 and the one under the block's left is item 3.
        XCTAssertEqual(LaunchpadHit.at(point(column: 3, row: 0, dx: w / 2, dy: LaunchpadMetrics.iconTop + 2), in: surface), .tile(address: 2, core: true))
        XCTAssertEqual(LaunchpadHit.at(point(column: 0, row: 1, dx: w / 2, dy: LaunchpadMetrics.iconTop + 2), in: surface), .tile(address: 3, core: true))
    }

    func testACellNoTileCoversIsTheGapAtTheEndOfThePage() {
        for (column, row) in [(1, 2), (2, 2), (3, 1), (g.columns - 1, 1), (0, g.rows - 1)] {
            XCTAssertEqual(LaunchpadHit.at(point(column: CGFloat(column), row: CGFloat(row), dx: 5, dy: 5), in: surface), .gap(address: 4), "\(column),\(row)")
        }
    }
}
