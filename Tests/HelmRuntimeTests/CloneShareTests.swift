import XCTest
@testable import HelmRuntime

/// What deleting a copy actually gives back.
///
/// On APFS a clone shares its blocks with the file it was made from — and
/// Finder's own Duplicate command makes clones, so this is the ordinary case,
/// not an exotic one. Measured on this machine: a 20 MB file cloned with
/// `cp -c` cost **0 bytes** of free space, while a real copy cost 20 MB, and
/// `stat` reported the same allocated size for both. So the size of a file is
/// not what removing it returns, and a duplicates screen that adds those sizes
/// up is promising space the disk will not give back.
final class CloneShareTests: XCTestCase {

    func testAnOrdinaryCopyGivesBackItsWholeSize() {
        XCTAssertEqual(
            CloneShare.reclaimable(removing: [(id: 2, bytes: 20_000_000)], keeping: [1]),
            20_000_000)
    }

    /// The case that made the old figure wrong. The copy shares every block
    /// with the one being kept, so the disk gains nothing.
    func testACloneOfTheKeptFileGivesBackNothing() {
        XCTAssertEqual(
            CloneShare.reclaimable(removing: [(id: 1, bytes: 20_000_000)], keeping: [1]),
            0, "a clone of the surviving copy was counted as space that comes back")
    }

    /// Two clones of each other, and neither is the survivor: the blocks go
    /// once, so they are worth one file between them and not two.
    func testTwoClonesOfEachOtherAreWorthOneFile() {
        XCTAssertEqual(
            CloneShare.reclaimable(removing: [(id: 7, bytes: 20_000_000),
                                              (id: 7, bytes: 20_000_000)],
                                   keeping: [1]),
            20_000_000)
    }

    func testMixedGroupCountsOnlyWhatComesBack() {
        // One real copy, one clone of the survivor, one pair of clones.
        XCTAssertEqual(
            CloneShare.reclaimable(removing: [(id: 2, bytes: 1_000),
                                              (id: 1, bytes: 8_000),
                                              (id: 9, bytes: 500), (id: 9, bytes: 500)],
                                   keeping: [1]),
            1_500)
    }

    /// A volume that is not APFS, or a file whose id could not be read, has no
    /// clone family — and guessing "shared" there would under-report space the
    /// person really does get back. Unknown counts as its own.
    func testAnUnknownIdCountsAsItsOwnFile() {
        XCTAssertEqual(
            CloneShare.reclaimable(removing: [(id: nil, bytes: 4_000), (id: nil, bytes: 4_000)],
                                   keeping: [nil]),
            8_000, "two files with no clone id were treated as one shared family")
    }

    func testNothingRemovedIsNothingReclaimed() {
        XCTAssertEqual(CloneShare.reclaimable(removing: [], keeping: [1]), 0)
    }

    /// Nothing kept: the last member of a clone family goes, so its blocks do
    /// come back — once.
    func testTheLastMemberOfAFamilyDoesFreeItsBlocks() {
        XCTAssertEqual(
            CloneShare.reclaimable(removing: [(id: 3, bytes: 5_000), (id: 3, bytes: 5_000)],
                                   keeping: []),
            5_000)
    }
}
