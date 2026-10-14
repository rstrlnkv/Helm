import XCTest
@testable import HelmRuntime

/// What a background scan may interrupt somebody for.
///
/// Three modules walk the volume twice a day and the whole user-visible product
/// of it was a relative date on a settings page — `ScanJournal.change(module:)`
/// computed the delta and nothing in `Sources/` ever called it. This is the rule
/// that decides when that delta is worth a banner, and every refusal below is a
/// banner somebody would otherwise have been shown for nothing.
final class AScanNobodyWatchedSaysWhatItFoundTests: XCTestCase {

    private func item(_ path: String, _ bytes: Int) -> ScanItem {
        ScanItem(path: path, bytes: bytes)
    }

    private func change(previous: [ScanItem]?, current: [ScanItem]) -> ScanChange {
        ScanComparison.between(previous: previous, current: current)
    }

    /// **A first scan has nothing to compare against, and a banner about it
    /// would be a claim about a change nobody measured.** `ScanChange` carries
    /// `hadPrevious` for exactly this, and the journal refuses to invent a
    /// previous list; the rule above it has to refuse too, or the first
    /// unattended scan of a full disk announces the whole disk as news.
    func testAFirstScanIsNotNews() {
        let first = change(previous: nil, current: [item("/a", 90_000_000_000)])
        XCTAssertNil(ScanNews.finding(in: first))
    }

    /// The floor is what keeps an hourly-feeling channel from becoming one. A
    /// few megabytes appearing between two scans is the disk working, not a
    /// finding.
    func testALittleThatAppearedIsNotWorthInterruptingAnybodyFor() {
        let small = change(previous: [], current: [item("/a", 4_000_000)])
        XCTAssertNil(ScanNews.finding(in: small, floor: 1_000_000_000))
    }

    /// Exactly the floor clears it: a threshold nothing can ever equal is a
    /// threshold written by accident.
    func testTheFloorIsClearedByReachingIt() {
        let exact = change(previous: [], current: [item("/a", 1_000_000_000)])
        XCTAssertNotNil(ScanNews.finding(in: exact, floor: 1_000_000_000))
    }

    /// **The numbers are what changed**, not the scan's total. A notice reading
    /// the whole finding would say the same 40 GB every day and mean «we looked
    /// again», which is the sentence this channel must never send.
    func testTheNumbersAreWhatAppearedAndNotWhatWasFound() {
        let moved = change(previous: [item("/kept", 80_000_000_000)],
                           current: [item("/kept", 80_000_000_000),
                                     item("/new-one", 2_000_000_000),
                                     item("/new-two", 3_000_000_000)])
        let finding = ScanNews.finding(in: moved, floor: 1_000_000_000)
        XCTAssertEqual(finding?.count, 2)
        XCTAssertEqual(finding?.bytes, 5_000_000_000)
    }

    /// Space that was *freed* is not news either, and it is the case a rule
    /// written against `isSomething` alone would get wrong: the person emptied
    /// their Downloads folder and Helm congratulated them for it.
    func testSpaceThatWentIsNotAnnounced() {
        let freed = change(previous: [item("/gone", 90_000_000_000)], current: [])
        XCTAssertNil(ScanNews.finding(in: freed, floor: 1_000_000_000))
    }

    /// An unchanged scan says nothing, which is the ordinary day.
    func testAScanThatFoundTheSameThingsAgainIsSilent() {
        let same = [item("/a", 90_000_000_000)]
        XCTAssertNil(ScanNews.finding(in: change(previous: same, current: same)))
    }

    /// The floor is a gigabyte, and it is named here rather than only at the
    /// call site: the default is what the app actually ships with, and a test
    /// that only ever passes its own threshold proves nothing about it.
    func testTheShippedFloorIsAGigabyte() {
        XCTAssertEqual(ScanNews.floorBytes, 1_000_000_000)
        let justUnder = change(previous: [], current: [item("/a", 999_999_999)])
        XCTAssertNil(ScanNews.finding(in: justUnder))
        let justOver = change(previous: [], current: [item("/a", 1_000_000_001)])
        XCTAssertNotNil(ScanNews.finding(in: justOver))
    }

    private let gigabyte = 1_000_000_000

    /// An item on both sides that grew by a megabyte is a megabyte of news, and
    /// the floor is asked of the megabyte. The item itself weighs six floors.
    func testAFolderThatGrewAMegabyteIsNotNews() {
        let grew = change(previous: [item("/Users/me/Downloads", 6 * gigabyte)],
                          current: [item("/Users/me/Downloads", 6 * gigabyte + 1_000_000)])
        XCTAssertNil(ScanNews.finding(in: grew))
    }

    /// The growth itself crossing the floor is news, and its weight is the
    /// growth: two gigabytes, one item.
    func testAFolderWhoseGrowthCrossesTheFloorIsCountedByTheGrowth() {
        let grew = change(previous: [item("/Users/me/Downloads", 6 * gigabyte)],
                          current: [item("/Users/me/Downloads", 8 * gigabyte)])
        let finding = ScanNews.finding(in: grew)
        XCTAssertEqual(finding?.count, 1)
        XCTAssertEqual(finding?.bytes, 2 * gigabyte)
    }

    /// An item that shrank is space that went, and it is silent like any other.
    func testAFolderThatShrankIsNotNews() {
        let shrank = change(previous: [item("/Users/me/Downloads", 6 * gigabyte)],
                            current: [item("/Users/me/Downloads", 5 * gigabyte)])
        XCTAssertNil(ScanNews.finding(in: shrank))
    }

    // MARK: - What counts as one item

    /// A new 2 GB item beside one that grew a megabyte: two items, the new one
    /// whole and the other by its growth.
    func testAGrownItemBesideANewOneCountsAsASecondItem() {
        let moved = change(previous: [item("/grew", 6 * gigabyte)],
                           current: [item("/grew", 6 * gigabyte + 1_000_000),
                                     item("/new", 2 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 2, bytes: 2 * gigabyte + 1_000_000))
    }

    /// A new 2 GB item beside one that shrank: one item, 2 GB.
    func testAShrunkItemBesideANewOneDoesNotCount() {
        let moved = change(previous: [item("/shrank", 3 * gigabyte)],
                           current: [item("/shrank", gigabyte),
                                     item("/new", 2 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 1, bytes: 2 * gigabyte))
    }

    /// One path listed twice in the newer list, once at the size it had before
    /// (that entry sits in `stayed`) and once at 3 GB (in `appeared`): one item,
    /// grown from 1 GB to 3 GB.
    func testAPathListedAtItsOldSizeAndAGrownOneCountsOnceByTheGrowth() {
        let moved = change(previous: [item("/a", gigabyte)],
                           current: [item("/a", gigabyte), item("/a", 3 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 1, bytes: 2 * gigabyte))
    }

    /// One path listed twice in the newer list at two sizes, neither the earlier
    /// one: one item, read at its larger size, 1 GB to 3 GB.
    func testAPathListedAtTwoNewSizesCountsOnceAtTheLarger() {
        let moved = change(previous: [item("/a", gigabyte)],
                           current: [item("/a", 2 * gigabyte), item("/a", 3 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 1, bytes: 2 * gigabyte))
    }

    /// The same with no earlier size at all: one new item, at its larger size.
    func testANewPathListedAtTwoSizesCountsOnceAtTheLarger() {
        let moved = change(previous: [],
                           current: [item("/a", 2 * gigabyte), item("/a", 3 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 1, bytes: 3 * gigabyte))
    }

    /// `testAPathListedAtTwoNewSizesCountsOnceAtTheLarger` and
    /// `testANewPathListedAtTwoSizesCountsOnceAtTheLarger` list the smaller size
    /// first; this lists the larger first, so a reading that keeps the last
    /// entry rather than the largest takes 2 GB here, and one that keeps the
    /// first takes 2 GB there.
    func testAPathListedLargerSizeFirstCountsOnceAtTheLarger() {
        let moved = change(previous: [item("/a", gigabyte)],
                           current: [item("/a", 3 * gigabyte), item("/a", 2 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 1, bytes: 2 * gigabyte))
    }

    /// The same for a path with no earlier size.
    func testANewPathListedLargerSizeFirstCountsOnceAtTheLarger() {
        let moved = change(previous: [],
                           current: [item("/a", 3 * gigabyte), item("/a", 2 * gigabyte)])
        XCTAssertEqual(ScanNews.finding(in: moved),
                       ScanNews.Finding(count: 1, bytes: 3 * gigabyte))
    }
}
