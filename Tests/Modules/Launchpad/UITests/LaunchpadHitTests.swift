import XCTest
@testable import Module_Launchpad_UI

/// What is under the pointer, from the geometry alone: no view is made.
final class LaunchpadHitTests: XCTestCase {
    private func surface(_ width: CGFloat, counts: [Int] = [10], page: Int = 0) -> LaunchpadSurface {
        LaunchpadSurface(geometry: .make(for: CGSize(width: width, height: 900), topSafe: 0), page: page, pageCounts: counts, gap: nil)
    }

    func testTheMiddleOfEveryTileHitsItsSlotAtEveryColumnCount() {
        var seen = Set<Int>()
        for width in [500, 700, 900, 1000, 1100, 1300, 1600] as [CGFloat] {
            let s = surface(width, counts: [6])
            seen.insert(s.geometry.columns)
            for slot in 0..<min(6, s.geometry.capacity) {
                XCTAssertEqual(LaunchpadHit.at(s.geometry.center(ofSlot: slot), in: s), .tile(address: slot, core: true), "\(width) slot \(slot)")
            }
        }
        XCTAssertTrue(seen.isSuperset(of: [3, 4, 5, 6, 7, 8]), "the widths cover 3 to 8 columns: \(seen)")
    }

    func testTheCoreIsTheIconsMiddleAndTheRestOfTheCellIsMargin() {
        let s = surface(1280)
        let c = s.geometry.center(ofSlot: 1)
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: c.x + s.geometry.cellWidth * 0.29, y: c.y), in: s), .tile(address: 1, core: true))
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: c.x + s.geometry.cellWidth * 0.35, y: c.y), in: s), .tile(address: 1, core: false))
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: c.x, y: c.y + s.geometry.cellHeight * 0.4), in: s), .tile(address: 1, core: false), "the label")
    }

    func testAShortLastRowKeepsItsColumnsAndTheEmptyCellsAreTheGrids() {
        let s = surface(1280, counts: [10])
        let columns = s.geometry.columns
        XCTAssertEqual(LaunchpadHit.at(s.geometry.center(ofSlot: 9), in: s), .tile(address: 9, core: true))
        XCTAssertEqual(LaunchpadHit.at(s.geometry.center(ofSlot: 10), in: s), .gap(address: 10))
        XCTAssertEqual(LaunchpadHit.at(s.geometry.center(ofSlot: columns), in: s), .tile(address: columns, core: true), "the second row begins at its own column 0")
    }

    func testAddressesCountFromThePagesFirstSlotWhateverThePagesBeforeHold() {
        let s = surface(1280, counts: [3, 5], page: 1)
        XCTAssertEqual(LaunchpadHit.at(s.geometry.center(ofSlot: 2), in: s), .tile(address: s.geometry.capacity + 2, core: true))
    }

    func testOutsideTheGridIsNothingAndTheSidesAreEdges() {
        let s = surface(1280)
        let g = s.geometry
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: 640, y: g.gridTop - 1), in: s), .none, "above the grid (the search field)")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: 640, y: g.gridTop + g.pageHeight), in: s), .none, "below it")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: g.origin(ofSlot: 0).x - 1, y: g.gridTop + 5), in: s), .none, "the margin between an edge and the first column")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: 10, y: g.gridTop + 5), in: s), .edge(-1))
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: g.size.width - 10, y: g.gridTop + 5), in: s), .edge(1))
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: 10, y: g.gridTop - 5), in: s), .none, "an edge is as high as the grid")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: CGFloat.nan, y: 5), in: s), .none)
    }

    func testTheCardIsCentredAndThePaddingAndTitleAreInIt() {
        let g = LaunchpadGeometry.make(for: CGSize(width: 1280, height: 800), topSafe: 0)
        let card = g.card(columns: 3, rows: 2)
        XCTAssertEqual(card.midX, 640, accuracy: 0.001)
        XCTAssertEqual(card.midY, 400, accuracy: 0.001)
        XCTAssertEqual(card.width, 3 * g.cellWidth + 2 * LaunchpadGeometry.cardPadding, accuracy: 0.001)
        XCTAssertEqual(card.height, 2 * g.cellHeight + LaunchpadGeometry.cardTitle + LaunchpadGeometry.cardGap + 2 * LaunchpadGeometry.cardPadding, accuracy: 0.001)
    }

    func testTheCardsTilesAreAddressedByTheirIndexInItAndNeverACore() {
        var s = surface(1280, counts: [10])
        let card = LaunchpadSurface.Card(geometry: s.geometry, count: s.geometry.columns)
        s.card = card
        XCTAssertEqual(card.rows, 2, "a short second row")
        for slot in 0..<card.count {
            XCTAssertEqual(LaunchpadHit.at(card.center(ofSlot: slot), in: s), .tile(address: slot, core: false), "slot \(slot)")
        }
        XCTAssertEqual(LaunchpadHit.at(card.center(ofSlot: card.count), in: s), .gap(address: card.count), "the cell after the last")
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: card.rect.midX, y: card.rect.minY + 4), in: s), .none, "the card's own title")
    }

    func testOutsideTheCardAndItsMarginIsAwayAndInsideTheMarginIsNot() {
        var s = surface(1280, counts: [10])
        let card = LaunchpadSurface.Card(geometry: s.geometry, count: 5)
        s.card = card
        let margin = LaunchpadLiftTiming.cardMargin
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: card.rect.minX - margin + 1, y: card.rect.midY), in: s), .none)
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: card.rect.minX - margin - 1, y: card.rect.midY), in: s), .away)
        XCTAssertEqual(LaunchpadHit.at(CGPoint(x: card.rect.midX, y: card.rect.maxY + margin + 1), in: s), .away)
        XCTAssertEqual(LaunchpadHit.at(s.geometry.center(ofSlot: 0), in: s), .away, "the grid under the card is not where the pointer is")
    }
}
