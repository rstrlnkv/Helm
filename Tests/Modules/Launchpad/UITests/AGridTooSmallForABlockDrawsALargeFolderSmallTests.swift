import XCTest
@testable import Module_Launchpad_UI

/// A grid under two cells a side has no room for a 2×2 block: a large folder is one cell there and nothing is lost or
/// overlapped. The window's own grids never get there (the settings keep two rows and three columns at least).
final class AGridTooSmallForABlockDrawsALargeFolderSmallTests: XCTestCase {
    func testUnderTwoRowsOrColumnsEveryLargeFolderIsOneCell() {
        for (c, r) in [(1, 1), (1, 5), (5, 1), (2, 1), (1, 2), (10, 1), (1, 8)] {
            let slots = LaunchpadPlacement.place([true, false, true, true, false], columns: c, rows: r)
            XCTAssertFalse(slots.isEmpty, "subject: something is placed \(c)x\(r)")
            XCTAssertTrue(slots.allSatisfy { $0.span == 1 }, "\(c)x\(r)")
            XCTAssertEqual(slots.count, min(5, c * r), "\(c)x\(r)")
            XCTAssertEqual(Set(slots.map { "\($0.column),\($0.row)" }).count, slots.count, "no overlap \(c)x\(r)")
        }
        let (pages, slots) = LaunchpadPaging.pages([Array(0..<7)], columns: 5, rows: 1, isLarge: { _ in true })
        XCTAssertEqual(pages.map(\.count), [5, 2])
        XCTAssertTrue(slots.joined().allSatisfy { $0.span == 1 })
    }

    func testNoSettingsMakeARealGridUnderTwoByThree() {
        for rows in [-3, 0, 1, 2, 5, 8, 50, Int.max] { for columns in [-3, 0, 1, 2, 3, 10, 50, Int.max] {
            for screen in [CGSize(width: 640, height: 400), CGSize(width: 1280, height: 800), CGSize(width: 3840, height: 2160)] {
                let g = LaunchpadGeometry.make(for: screen, topSafe: 0, settings: LaunchpadGridSettings(automatic: false, rows: rows, columns: columns, iconSize: 80))
                XCTAssertGreaterThanOrEqual(g.rows, 2, "\(rows)x\(columns) on \(screen)")
                XCTAssertGreaterThanOrEqual(g.columns, 2, "\(rows)x\(columns) on \(screen)")
                XCTAssertEqual(LaunchpadPlacement.place([true], columns: g.columns, rows: g.rows).first?.span, 2, "subject: a block fits")
            }
        } }
    }
}
