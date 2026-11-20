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

    // MARK: A card with pages

    private func pagedCard(count: Int, page: Int) -> (LaunchpadSurface, LaunchpadSurface.Card) {
        var s = surface(1280, counts: [10])
        let card = LaunchpadSurface.Card(geometry: s.geometry, count: count, page: page)
        s.card = card
        return (s, card)
    }

    private var oneCardPage: Int { LaunchpadSurface.Card(geometry: surface(1280).geometry, count: 10_000).capacity }

    func testAPagedCardAnswersEveryTileByItsIndexInTheWholeListOnTheShownPage() {
        let cap = oneCardPage
        for page in 0...2 {
            let (s, card) = pagedCard(count: 2 * cap + 3, page: page)
            XCTAssertEqual(card.pageCount, 3)
            for slot in 0..<cap {
                let index = page * cap + slot
                let expected: LaunchpadHit = index < card.count ? .tile(address: index, core: false) : .gap(address: index)
                XCTAssertEqual(LaunchpadHit.at(card.center(ofSlot: slot), in: s), expected, "page \(page) slot \(slot)")
            }
        }
        let (s, card) = pagedCard(count: 2 * cap + 3, page: 2)
        XCTAssertEqual(LaunchpadHit.at(card.center(ofSlot: 3), in: s), .gap(address: 2 * cap + 3), "the short last page: the cell after the last")
    }

    func testACardsEdgeStripsAreThereOnlyWhenItHasPages() {
        let cap = oneCardPage
        for (count, paged) in [(cap, false), (cap + 1, true), (1, false), (0, false)] {
            let (s, card) = pagedCard(count: count, page: 0)
            XCTAssertEqual(card.paged, paged, "\(count)")
            let pad = LaunchpadGeometry.cardPadding / 2, margin = LaunchpadLiftTiming.cardMargin / 2
            let strips: [(String, CGFloat, CGFloat)] = [("padding", card.origin.x - pad, card.origin.x + card.pageWidth + pad),
                                                        ("margin", card.rect.minX - margin, card.rect.maxX + margin)]
            for (name, left, right) in strips {
                XCTAssertEqual(LaunchpadHit.at(CGPoint(x: left, y: card.rect.midY), in: s), paged ? .edge(-1) : .none, "\(count) left \(name)")
                XCTAssertEqual(LaunchpadHit.at(CGPoint(x: right, y: card.rect.midY), in: s), paged ? .edge(1) : .none, "\(count) right \(name)")
            }
        }
    }

    func testACardsPageIsHeldInsideItsPagesAndACardOfNothingHasOne() {
        let cap = oneCardPage
        let g = surface(1280).geometry
        XCTAssertEqual(LaunchpadSurface.Card(geometry: g, count: 2 * cap, page: 99).page, 1)
        XCTAssertEqual(LaunchpadSurface.Card(geometry: g, count: 2 * cap, page: -3).page, 0)
        XCTAssertEqual(LaunchpadSurface.Card(geometry: g, count: 2 * cap, page: .max).page, 1)
        let empty = LaunchpadSurface.Card(geometry: g, count: 0, page: 4)
        XCTAssertEqual(empty.page, 0)
        XCTAssertEqual(empty.pageCount, 1)
        XCTAssertGreaterThanOrEqual(empty.capacity, 1)
        XCTAssertTrue(empty.range(ofPage: 0).isEmpty)
        XCTAssertTrue(empty.range(ofPage: 7).isEmpty)
        XCTAssertEqual(empty.page(ofIndex: 5), 0)
        XCTAssertEqual(empty.page(ofIndex: -5), 0)
    }

    func testThePagesRangesCutTheListWithoutAGapOrAnOverlapAndEveryIndexFindsItsPage() {
        let cap = oneCardPage
        let g = surface(1280).geometry
        for count in [1, cap - 1, cap, cap + 1, 2 * cap, 2 * cap + 1, 5 * cap + 7] {
            let card = LaunchpadSurface.Card(geometry: g, count: count)
            var next = 0
            for page in 0..<card.pageCount {
                let range = card.range(ofPage: page)
                XCTAssertEqual(range.lowerBound, next, "\(count) page \(page)")
                XCTAssertFalse(range.isEmpty, "\(count): no empty page")
                next = range.upperBound
            }
            XCTAssertEqual(next, count, "\(count): the ranges end at the list's end")
            XCTAssertEqual(card.pageCount, (count + cap - 1) / cap)
            for index in 0..<count { XCTAssertTrue(card.range(ofPage: card.page(ofIndex: index)).contains(index), "\(count) index \(index)") }
            XCTAssertTrue(card.range(ofPage: card.pageCount).isEmpty, "a page past the end holds nothing")
            XCTAssertTrue(card.range(ofPage: -1).isEmpty || card.range(ofPage: -1) == card.range(ofPage: 0), "a page before the first holds nothing or the first, never a crash")
            XCTAssertEqual(card.page(ofIndex: .max), card.pageCount - 1)
        }
    }
}
