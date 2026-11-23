import XCTest
@testable import Module_Launchpad_UI

/// A page's cells come from one function. Over every pattern of large and small tiles and every grid the settings allow: no two
/// tiles share a cell, each lies inside the grid, the placed run is the longest one that fits, a page of small tiles is today's
/// grid, and the pages cut from a list hold it whole, in order, with no empty page.
final class PlacementNeverOverlapsAndLosesNothingTests: XCTestCase {
    private typealias Slot = LaunchpadPlacement.Slot

    private func patterns(upTo length: Int) -> [[Bool]] {
        (0...length).flatMap { n in (0..<(1 << n)).map { bits in (0..<n).map { bits >> $0 & 1 == 1 } } }
    }

    private func cells(_ s: Slot) -> [Int] { (s.row..<s.row + s.span).flatMap { r in (s.column..<s.column + s.span).map { r * 100 + $0 } } }

    func testNoTwoTilesShareACellAndEveryTileIsInsideTheGrid() {
        var large = 0
        for columns in 3...10 { for rows in 2...8 {
            for pattern in patterns(upTo: 8) {
                let slots = LaunchpadPlacement.place(pattern, columns: columns, rows: rows)
                XCTAssertLessThanOrEqual(slots.count, columns * rows)
                var seen = Set<Int>()
                for (i, s) in slots.enumerated() {
                    XCTAssertEqual(s.span, pattern[i] ? 2 : 1, "\(pattern) \(columns)x\(rows)")
                    large += s.span == 2 ? 1 : 0
                    XCTAssertTrue(s.column >= 0 && s.row >= 0 && s.column + s.span <= columns && s.row + s.span <= rows, "\(pattern) \(columns)x\(rows) \(s)")
                    for c in cells(s) { XCTAssertTrue(seen.insert(c).inserted, "overlap \(pattern) \(columns)x\(rows)") }
                }
            }
        } }
        XCTAssertGreaterThan(large, 0, "subject: blocks were placed")
    }

    func testThePlacedRunIsTheLongestThatFits() {
        for columns in [3, 4, 5, 10] { for rows in [2, 3, 8] {
            for pattern in patterns(upTo: 8) {
                let slots = LaunchpadPlacement.place(pattern, columns: columns, rows: rows)
                guard slots.count < pattern.count else { continue }
                // The first item that did not fit has no free place among the cells the run left.
                let taken = Set(slots.flatMap(cells))
                let span = pattern[slots.count] ? 2 : 1
                for r in 0...(rows - span) { for c in 0...(columns - span) {
                    let free = (0..<span).allSatisfy { dr in (0..<span).allSatisfy { dc in !taken.contains((r + dr) * 100 + c + dc) } }
                    XCTAssertFalse(free, "\(pattern) \(columns)x\(rows): item \(slots.count) fits at \(c),\(r)")
                } }
            }
        } }
        XCTAssertTrue(LaunchpadPlacement.place([true, true, true, true, true], columns: 3, rows: 2).count < 5, "subject: something overflowed")
    }

    func testSmallTilesOnlyAreTodaysGrid() {
        for columns in 3...10 { for rows in 2...8 {
            let slots = LaunchpadPlacement.place([Bool](repeating: false, count: columns * rows + 3), columns: columns, rows: rows)
            XCTAssertEqual(slots.count, columns * rows)
            XCTAssertEqual(slots, (0..<columns * rows).map { Slot(column: $0 % columns, row: $0 / columns, span: 1) })
        } }
    }

    func testASmallTileFillsTheStripABlockSkipped() {
        // A block at the last column's left neighbour cannot be there: it goes to the next row and the small tile takes the strip.
        let slots = LaunchpadPlacement.place([false, false, true, false], columns: 3, rows: 4)
        XCTAssertEqual(slots, [Slot(column: 0, row: 0, span: 1), Slot(column: 1, row: 0, span: 1),
                               Slot(column: 0, row: 1, span: 2), Slot(column: 2, row: 0, span: 1)])
    }

    func testNoRoomForABlockDrawsItSmall() {
        XCTAssertEqual(LaunchpadPlacement.place([true, false], columns: 1, rows: 5).map(\.span), [1, 1])
        XCTAssertEqual(LaunchpadPlacement.place([true], columns: 5, rows: 1).map(\.span), [1])
        XCTAssertEqual(LaunchpadPlacement.place([true], columns: 0, rows: 3), [])
    }

    func testPagesHoldTheListWholeInOrderWithNoEmptyPage() {
        for (columns, rows) in [(3, 2), (4, 2), (5, 3), (10, 8)] {
            for pattern in patterns(upTo: 7) + [Array((0..<40).map { $0 % 3 == 0 })] {
                let items = Array(pattern.indices)
                let segments = [Array(items.prefix(items.count / 2)), Array(items.dropFirst(items.count / 2))]
                let (pages, slots) = LaunchpadPaging.pages(segments, columns: columns, rows: rows, isLarge: { pattern[$0] })
                XCTAssertEqual(pages.flatMap { $0 }, items, "\(pattern) \(columns)x\(rows)")
                XCTAssertEqual(pages.map(\.count), slots.map(\.count))
                if !items.isEmpty { XCTAssertTrue(pages.allSatisfy { !$0.isEmpty }, "\(pattern) \(columns)x\(rows)") }
                XCTAssertTrue(pages.allSatisfy { $0.count <= columns * rows })
            }
        }
        XCTAssertEqual(LaunchpadPaging.pages([[Int]]() + [[]], columns: 3, rows: 2, isLarge: { _ in true }).pages, [[]])
    }
}
