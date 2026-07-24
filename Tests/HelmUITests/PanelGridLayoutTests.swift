import XCTest
@testable import HelmUI

final class PanelGridLayoutTests: XCTestCase {
    func testCompactTilesPairUp() {
        XCTAssertEqual(PanelGridLayout.rows(of: [.compact, .compact]), [[0, 1]])
    }

    func testWideTakesItsOwnRow() {
        XCTAssertEqual(PanelGridLayout.rows(of: [.wide, .compact, .compact]), [[0], [1, 2]])
    }

    /// A wide tile between compacts must not let the earlier compact "jump" it.
    func testWideFlushesPendingCompactFirst() {
        XCTAssertEqual(PanelGridLayout.rows(of: [.compact, .wide, .compact]), [[0], [1], [2]])
    }

    func testTrailingCompactKeepsOwnRow() {
        XCTAssertEqual(PanelGridLayout.rows(of: [.compact, .compact, .compact]), [[0, 1], [2]])
    }

    func testEmpty() {
        XCTAssertEqual(PanelGridLayout.rows(of: []), [])
    }
}
