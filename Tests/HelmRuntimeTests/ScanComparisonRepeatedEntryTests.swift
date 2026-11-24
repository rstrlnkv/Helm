import XCTest
@testable import HelmRuntime

/// One repeated entry, on each side in turn.
///
/// A repeated entry is counted once on either side: `went` is read from a
/// set, and `appeared` and `stayed` must be too, because the byte totals the
/// journal draws are `reduce` over those arrays.
final class ScanComparisonRepeatedEntryTests: XCTestCase {

    /// The mirror of the existing `testARepeatedPathDoesNotBreakTheComparison`,
    /// which puts the repeat on the previous side only.
    func testARepeatedEntryInTheCurrentListAppearsOnce() {
        let change = ScanComparison.between(previous: [],
                                            current: [item("/a", 10), item("/a", 10)])
        XCTAssertEqual(change.appeared.map(\.path), ["/a"],
                       "one file was reported as two arrivals")
        XCTAssertEqual(change.appearedBytes, 10,
                       "the bytes of one file were counted twice")
    }

    /// The same on the unchanged side, which is what a page's "still there"
    /// figure is drawn from.
    func testARepeatedEntryThatStayedIsCountedOnce() {
        let change = ScanComparison.between(previous: [item("/a", 10)],
                                            current: [item("/a", 10), item("/a", 10)])
        XCTAssertEqual(change.stayed.map(\.path), ["/a"])
        XCTAssertEqual(change.stayed.map(\.bytes), [10])
    }
}
