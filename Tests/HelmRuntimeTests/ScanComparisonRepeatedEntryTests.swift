import XCTest
@testable import HelmRuntime

/// One repeated entry, on each side in turn.
///
/// `ScanComparison.between` already argues the case for the previous side, in
/// its own comment on `went`:
///
/// > From the set, so a previous list carrying the same entry twice does not
/// > report one departure twice.
///
/// `appeared` and `stayed` are plain filters over `current` and get no such
/// treatment, so the identical input on the identical structure is handled two
/// different ways. The byte totals the journal draws are `reduce` over those
/// arrays, so the asymmetry is not cosmetic: it is one number twice.
final class ScanComparisonRepeatedEntryTests: XCTestCase {

    private func item(_ path: String, _ bytes: Int) -> ScanItem {
        ScanItem(path: path, bytes: bytes)
    }

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
        XCTAssertEqual(change.stayedBytes, 10)
    }
}
