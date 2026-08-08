import XCTest
@testable import HelmUI

/// The panel's arithmetic, argued with rather than looked at.
///
/// Every rule here was executable in the mockups before it was Swift — seven
/// live panels that could be resized and rearranged — and the reason it is
/// pure here is the same reason it was an engine there: a rule you cannot try
/// is not a rule.
final class PanelGridTests: XCTestCase {

    // MARK: - Columns

    /// The width decides how many columns fit, never how narrow a tile gets.
    func testColumnsAtTheWidthsThatMatter() {
        XCTAssertEqual(PanelGrid.columns(for: 320), 2)   // the panel Helm ships
        XCTAssertEqual(PanelGrid.columns(for: 400), 2)   // 3 would be 120 pt a tile
        XCTAssertEqual(PanelGrid.columns(for: 480), 3)
    }

    /// Two, whatever happens. One column is a list, and the sizes stop meaning
    /// anything the moment `wide` and `compact` are the same width.
    func testNeverFewerThanTwoColumns() {
        for width in [0, 100, 160, 200] as [CGFloat] {
            XCTAssertGreaterThanOrEqual(PanelGrid.columns(for: CGFloat(width)), 2)
        }
    }

    /// The floor the column count is argued from: a tile is never narrower
    /// than 144 pt.
    ///
    /// **The `columns == 2` escape is gone.** It was there because two columns
    /// is the minimum and a narrow panel cannot honour the floor — which is
    /// true, and it exempted every width the app actually uses: at the 300 pt
    /// the panel shipped at, two columns are 134 pt and the assertion could not
    /// fail. A test that names a rule and then excuses the only case it governs
    /// is a comment with a `func` in front of it.
    func testATileIsNeverNarrowerThanTheFloor() {
        for width in stride(from: PanelGrid.narrowestPanel, through: 900, by: 4) {
            let tile = PanelGrid.tileWidth(for: width)
            XCTAssertGreaterThanOrEqual(tile, PanelGrid.minimumTile,
                                        "\(width) pt buys \(PanelGrid.columns(for: width)) columns of \(tile) pt")
        }
    }

    /// And the width the panel is actually drawn at is one of those.
    func testTheShippedWidthClearsIt() {
        XCTAssertGreaterThanOrEqual(PanelGrid.tileWidth(for: 320), PanelGrid.minimumTile)
    }

    // MARK: - A size that is no longer offered

    func testAnOfferedSizeIsGivenAsAsked() {
        XCTAssertEqual(PanelGrid.resolve(.tall, offered: [.compact, .wide, .tall]), .tall)
    }

    /// Clamped to the nearest, never dropped: somebody arranged this panel,
    /// and a layout that quietly loses a member is one nobody trusts.
    func testAMissingSizeClampsToItsNeighbour() {
        XCTAssertEqual(PanelGrid.resolve(.tall, offered: [.compact, .wide]), .wide)
        XCTAssertEqual(PanelGrid.resolve(.compact, offered: [.wide, .tall]), .wide)
        XCTAssertEqual(PanelGrid.resolve(.wide, offered: [.compact]), .compact)
    }

    /// A module that offers nothing has no widget, which is different from a
    /// module whose widget got smaller.
    func testAModuleThatOffersNothingHasNoWidget() {
        XCTAssertNil(PanelGrid.resolve(.wide, offered: []))
    }

    // MARK: - Packing

    /// A full-width widget is a row of its own and interrupts whatever row was
    /// being filled — it cannot share, so the compact ones before it keep the
    /// row they had started.
    func testAFullWidthWidgetTakesItsOwnRow() {
        XCTAssertEqual(PanelGrid.rows(sizes: [.compact, .wide, .compact], columns: 2),
                       [[0], [1], [2]])
    }

    func testCompactWidgetsFillARowAndStartAnother() {
        XCTAssertEqual(PanelGrid.rows(sizes: [.compact, .compact, .compact], columns: 2),
                       [[0, 1], [2]])
        XCTAssertEqual(PanelGrid.rows(sizes: [.compact, .compact, .compact], columns: 3),
                       [[0, 1, 2]])
    }

    /// Today's panel is this grid's own special case: every widget full width,
    /// so every row holds one. That is what makes the first commit invisible.
    func testAllWideIsTodaysPanel() {
        let sizes = [PanelWidgetSize](repeating: .wide, count: 5)
        XCTAssertEqual(PanelGrid.rows(sizes: sizes, columns: 2), [[0], [1], [2], [3], [4]])
    }

    /// The control: no widget is lost and none is drawn twice, whatever the
    /// arrangement. Every assertion above is about a handful of shapes; this
    /// is about all of them.
    func testEveryWidgetAppearsExactlyOnce() {
        let alphabet: [PanelWidgetSize] = [.compact, .wide, .tall]
        for count in 0...7 {
            for seed in 0..<27 {
                var n = seed
                let sizes = (0..<count).map { _ -> PanelWidgetSize in
                    defer { n /= 3 }
                    return alphabet[n % 3]
                }
                for columns in 2...4 {
                    let flat = PanelGrid.rows(sizes: sizes, columns: columns).flatMap { $0 }
                    XCTAssertEqual(flat, Array(0..<count),
                                   "\(sizes) at \(columns) columns came back as \(flat)")
                }
            }
        }
    }

    // MARK: - What the grid is left after the pinned bars

    /// The strip is measured, and until it has been the panel still has to draw
    /// something. Nothing measured means the whole ceiling, not nothing at all.
    ///
    /// Spelled as the number rather than as «the same as the ceiling»: two
    /// calls of the same function agree with each other whatever it returns,
    /// including the zero a stub returns, and a check that cannot fail is not a
    /// check.
    func testAnUnmeasuredStripIsTheWholeCeiling() {
        let ceiling = PanelGrid.maximumHeight - PanelGrid.padding * 2 - PanelGrid.gap
        XCTAssertEqual(PanelGrid.roomForGrid(strip: 0, top: nil, foot: nil), ceiling)
    }

    /// A tall display does not buy a taller panel: past `maximumHeight` the
    /// grid scrolls.
    func testTheCeilingHoldsOnATallDisplay() {
        let ceiling = PanelGrid.maximumHeight - PanelGrid.padding * 2 - PanelGrid.gap
        XCTAssertEqual(PanelGrid.roomForGrid(strip: 4000, top: nil, foot: nil), ceiling)
    }

    /// **A bar that is not drawn reserves nothing — either bar.**
    ///
    /// The shipped defect: the "is it drawn" test was applied to the tab strip
    /// and not to the footer, so switching the last footer button off left 38 pt
    /// reserved under a footer that had stopped being drawn, and a grid that had
    /// exactly fitted began to scroll. `nil` is the bar's absence; its last
    /// measurement is not an answer about a bar nobody draws.
    ///
    /// The strip gives back its gap along with its height, because the block
    /// itself goes away with it; the footer block's height is all it has to
    /// give, because the block is drawn empty. The next two tests are each of
    /// those halves on its own.
    func testABarThatIsNotDrawnReservesNothing() {
        let both = PanelGrid.roomForGrid(strip: 600, top: 30, foot: 38)
        XCTAssertEqual(PanelGrid.roomForGrid(strip: 600, top: 30, foot: nil), both + 38)
        XCTAssertEqual(PanelGrid.roomForGrid(strip: 600, top: nil, foot: 38), both + 38)
        XCTAssertEqual(PanelGrid.roomForGrid(strip: 600, top: nil, foot: nil), both + 76)
    }

    /// **And it does not reserve the gap that bar would have made either.**
    ///
    /// The card is three blocks with 8 pt between them, and only the tab strip
    /// is conditional — so the gaps *drawn* are two when the strip is there and
    /// one when it is not, while the arithmetic took two unconditionally. The
    /// default panel is one tab, which is no strip: it was handed 8 pt less
    /// than the card had, and paid for it with a scrollbar and a clipped tile.
    ///
    /// Stated as a difference between two calls rather than as the formula
    /// again: a term spelled twice agrees with itself whatever it is.
    func testAStripThatIsNotDrawnTakesItsGapWithIt() {
        let drawn = PanelGrid.roomForGrid(strip: 600, top: 30, foot: 38)
        let absent = PanelGrid.roomForGrid(strip: 600, top: nil, foot: 38)
        XCTAssertEqual(absent - drawn, 30 + PanelGrid.gap,
                       "the grid still pays 8 pt for a gap under a strip nobody draws")
    }

    /// The footer block is the other way round, and that asymmetry is the
    /// point. It is drawn unconditionally — an empty `VStack` with no height —
    /// and the stack still spends its neighbour's spacing on it, so its gap is
    /// there whether or not anything is in it. `foot` says how *tall* it is,
    /// never whether the gap above it exists.
    func testTheFooterBlocksGapIsThereEvenWhenTheFooterIsNot() {
        let full = PanelGrid.roomForGrid(strip: 600, top: 30, foot: 38)
        let empty = PanelGrid.roomForGrid(strip: 600, top: 30, foot: nil)
        XCTAssertEqual(empty - full, 38)
    }

    /// A very short strip still shows something to scroll rather than a sliver.
    func testNeverLessThanARow() {
        XCTAssertEqual(PanelGrid.roomForGrid(strip: 60, top: 300, foot: 300), 120)
    }

    /// The bars come off the ceiling, and so do the card's own padding and the
    /// gaps between its blocks — the panel is 12 pt inside and 8 pt between.
    func testTheCardsOwnEdgesComeOffToo() {
        let room = PanelGrid.roomForGrid(strip: 500, top: nil, foot: nil)
        XCTAssertEqual(room, 500 - PanelGrid.padding * 2 - PanelGrid.gap)
    }

    /// The control's control: a row never holds more than the grid has room
    /// for, and a full-width widget never shares one.
    func testNoRowOverflows() {
        let alphabet: [PanelWidgetSize] = [.compact, .wide, .tall]
        for seed in 0..<81 {
            var n = seed
            let sizes = (0..<4).map { _ -> PanelWidgetSize in
                defer { n /= 3 }
                return alphabet[n % 3]
            }
            for columns in 2...4 {
                for row in PanelGrid.rows(sizes: sizes, columns: columns) {
                    XCTAssertLessThanOrEqual(row.count, columns)
                    if row.contains(where: { sizes[$0].isFullWidth }) {
                        XCTAssertEqual(row.count, 1, "a full-width widget shared a row")
                    }
                }
            }
        }
    }
}
