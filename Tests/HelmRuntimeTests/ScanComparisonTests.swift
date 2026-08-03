import XCTest
@testable import HelmRuntime

final class ScanComparisonTests: XCTestCase {

    private func item(_ path: String, _ bytes: Int) -> ScanItem {
        ScanItem(path: path, bytes: bytes)
    }

    func testNothingChanged() {
        let list = [item("/a", 10), item("/b", 20)]
        let change = ScanComparison.between(previous: list, current: list)
        XCTAssertTrue(change.appeared.isEmpty)
        XCTAssertTrue(change.went.isEmpty)
        XCTAssertEqual(change.stayed.count, 2)
        XCTAssertFalse(change.isSomething)
    }

    func testAppearedAndWent() {
        let change = ScanComparison.between(previous: [item("/a", 10), item("/b", 20)],
                                            current: [item("/b", 20), item("/c", 30)])
        XCTAssertEqual(change.appeared.map(\.path), ["/c"])
        XCTAssertEqual(change.went.map(\.path), ["/a"])
        XCTAssertEqual(change.stayed.map(\.path), ["/b"])
        XCTAssertTrue(change.isSomething)
    }

    /// A file at the same path with a different size is not the same file for
    /// this purpose: something happened to it, and a comparison that reported
    /// «ничего не изменилось» would be wrong about the only thing it measures.
    /// It is reported as gone *and* appeared, which is what the numbers need —
    /// the old bytes leave the total and the new ones enter it.
    func testAPathThatChangedSizeCountsAsBoth() {
        let change = ScanComparison.between(previous: [item("/a", 10)],
                                            current: [item("/a", 99)])
        XCTAssertEqual(change.appeared.map(\.bytes), [99])
        XCTAssertEqual(change.went.map(\.bytes), [10])
        XCTAssertTrue(change.stayed.isEmpty)
    }

    /// The figures the page shows. `appearedBytes` is what the last scan added
    /// to the offer, not the whole offer.
    func testTheByteTotals() {
        let change = ScanComparison.between(
            previous: [item("/a", 10), item("/b", 20)],
            current: [item("/b", 20), item("/c", 30), item("/d", 5)])
        XCTAssertEqual(change.appearedBytes, 35)
        XCTAssertEqual(change.wentBytes, 10)
        XCTAssertEqual(change.stayedBytes, 20)
    }

    /// A first scan has nothing behind it. Everything is new, and that must not
    /// read as "35 GB appeared since yesterday" on a page that has only ever run
    /// once — the caller checks `hadPrevious` before drawing a delta.
    func testAFirstScanHasNoPrevious() {
        let change = ScanComparison.between(previous: nil,
                                            current: [item("/a", 10)])
        XCTAssertFalse(change.hadPrevious)
        XCTAssertEqual(change.appeared.count, 1)
        XCTAssertTrue(change.went.isEmpty)
    }

    /// An empty previous list is not the same as no previous list: the scan ran
    /// and found nothing, so a file appearing since then really did appear.
    func testAnEmptyPreviousIsStillAPrevious() {
        let change = ScanComparison.between(previous: [], current: [item("/a", 10)])
        XCTAssertTrue(change.hadPrevious)
        XCTAssertEqual(change.appeared.count, 1)
    }

    /// Two entries for one path is a scan that double-counted, or a list
    /// somebody edited. Neither should make the comparison lose the second one
    /// silently or crash on a duplicate key.
    func testARepeatedPathDoesNotBreakTheComparison() {
        let change = ScanComparison.between(previous: [item("/a", 10), item("/a", 10)],
                                            current: [item("/a", 10)])
        XCTAssertTrue(change.appeared.isEmpty)
        XCTAssertEqual(change.stayed.map(\.path), ["/a"])
    }

    /// Order in, order out. A page that lists what appeared should not reshuffle
    /// it between two draws of the same data.
    func testTheOrderOfTheCurrentListIsKept() {
        let change = ScanComparison.between(
            previous: [],
            current: [item("/z", 1), item("/a", 2), item("/m", 3)])
        XCTAssertEqual(change.appeared.map(\.path), ["/z", "/a", "/m"])
    }
}
