import XCTest
@testable import Module_Launchpad_Engine
@testable import Module_Launchpad_UI

/// On a page that holds a large folder the Up and Down keys follow the cells: the tile above or below the block's left
/// column, nothing above the first row or below the last (the choice stays); Left and Right keep the stored order; a page
/// with no block keeps the old rule of stepping a row of the page's columns.
@MainActor final class TheArrowKeysFollowTheCellsAroundALargeFolderTests: XCTestCase {
    private let folderID = UUID()
    private let screen = CGSize(width: 1920, height: 1080)

    /// The stored order: a, b, the block, then the rest; 60 items so there is a second page.
    private func order(_ count: Int = 60) -> [String] {
        ["a", "b", folderID.uuidString] + (0..<count).map { String(format: "t%02d", $0) }
    }

    private func rig(large: Bool = true, count: Int = 60) -> LiftRig {
        let rest = (0..<count).map { String(format: "t%02d", $0) }
        let items: [LaunchpadLayout.Item] = [.app("a"), .app("b"), .folder(.init(id: folderID, name: "F", apps: ["y", "z", "z2"], large: large))] + rest.map { .app($0) }
        return LiftRig(self, apps: ["a", "b", "y", "z", "z2"] + rest, layout: LaunchpadLayout(items: items), screen: screen)
    }

    private func select(_ r: LiftRig, _ index: Int) {
        if r.state.selection == nil { r.state.move(dx: 1, dy: 0) }
        var steps = 0
        while let at = r.state.selection, at != index, steps < 200 { r.state.move(dx: at < index ? 1 : -1, dy: 0); steps += 1 }
        XCTAssertEqual(r.state.selection, index, "subject: the choice is on \(index)")
    }

    private func id(_ r: LiftRig, _ flat: Int?) -> String? { flat.flatMap { r.state.pages.joined().dropFirst($0).first?.id } }

    func testDownAndUpWalkTheCellsAroundTheBlock() {
        let r = rig()
        let c = r.g.columns
        XCTAssertGreaterThanOrEqual(c, 5, "subject: room for a strip beside the block")
        XCTAssertGreaterThanOrEqual(r.g.rows, 3, "subject: a row below the block")
        XCTAssertEqual(r.state.slots[0][2].span, 2, "subject: the folder is a block")
        let o = order()
        // Row 0: a b [F F] then c-4 tiles; row 1: two tiles, [F F], c-4 tiles; row 2 starts at 2c-3.
        let below = [0: c - 1, 1: c, 2: 2 * c - 1]
        for (from, to) in below {
            select(r, from)
            r.state.move(dx: 0, dy: 1)
            XCTAssertEqual(id(r, r.state.selection), o[to], "Down from \(o[from]) is \(o[to])")
            r.state.move(dx: 0, dy: -1)
            XCTAssertEqual(r.state.selection, from, "Up comes back")
        }
        // Up from under the block's right half is the block; Up from its left column too.
        select(r, 2 * c)
        r.state.move(dx: 0, dy: -1)
        XCTAssertEqual(r.state.selection, 2, "Up from the cell under the block's right half")
    }

    func testNothingAboveTheFirstRowOrBelowTheLastRowStays() {
        let r = rig()
        let page0 = r.state.pages[0].count
        for first in [0, 1, 2] {
            select(r, first)
            r.state.move(dx: 0, dy: -1)
            XCTAssertEqual(r.state.selection, first, "nothing above row 0")
        }
        // The last tile of the page's last row, and any tile of its last row, has nothing below.
        let lastRow = r.state.slots[0].indices.filter { r.state.slots[0][$0].row + r.state.slots[0][$0].span == r.g.rows }
        XCTAssertFalse(lastRow.isEmpty, "subject: the page fills its rows")
        for i in lastRow {
            select(r, i)
            r.state.move(dx: 0, dy: 1)
            XCTAssertEqual(r.state.selection, i, "nothing below the last row at \(i)")
            XCTAssertEqual(r.state.page, 0)
        }
        XCTAssertLessThan(page0, 60, "subject: the block cost room")
    }

    func testLeftAndRightKeepTheStoredOrderAcrossTheBlock() {
        let r = rig()
        select(r, 1)
        r.state.move(dx: 1, dy: 0)
        XCTAssertEqual(r.state.selection, 2)
        r.state.move(dx: 1, dy: 0)
        XCTAssertEqual(r.state.selection, 3, "the block is one stop")
        r.state.move(dx: -1, dy: 0)
        XCTAssertEqual(r.state.selection, 2)
    }

    func testAPageWithNoBlockKeepsTheOldRule() {
        let r = rig(large: false)
        let c = r.g.columns
        for from in [0, 3, c + 1] {
            select(r, from)
            r.state.move(dx: 0, dy: 1)
            XCTAssertEqual(r.state.selection, from + c, "all small: Down is a row of the page's columns")
        }
        // A block on page 0 does not change the second page: it has none.
        let big = rig()
        let second = big.state.pages[0].count
        XCTAssertLessThan(second, big.g.capacity, "subject: page 0 holds fewer tiles")
        XCTAssertTrue(big.state.slots[1].allSatisfy { $0.span == 1 }, "subject: page 1 has no block")
        select(big, second + 1)
        XCTAssertEqual(big.state.page, 1)
        big.state.move(dx: 0, dy: 1)
        XCTAssertEqual(big.state.selection, second + 1 + c, "page 1 steps a row of columns")
    }
}
