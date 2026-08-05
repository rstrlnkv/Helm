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
        XCTAssertEqual(PanelGrid.columns(for: 300), 2)   // the panel Helm ships
        XCTAssertEqual(PanelGrid.columns(for: 320), 2)
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
    /// than 144 pt *because another column was fitted in*.
    func testAnExtraColumnIsNeverBoughtBelowTheFloor() {
        for width in stride(from: CGFloat(300), through: 900, by: 4) {
            let tile = PanelGrid.tileWidth(for: width)
            let columns = PanelGrid.columns(for: width)
            XCTAssertTrue(columns == 2 || tile >= PanelGrid.minimumTile,
                          "\(width) pt buys \(columns) columns of \(tile) pt")
        }
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
