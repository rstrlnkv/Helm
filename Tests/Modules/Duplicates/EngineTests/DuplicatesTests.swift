import XCTest
@testable import Module_Duplicates_Engine

/// The second look inside the disk: files that are the same file twice.
///
/// The rules under test are the ones that keep the feature from lying. Size
/// alone is coincidence, so equal size only nominates candidates; content
/// decides. Two paths with one inode are one file wearing two names — calling
/// them duplicates would offer to "free" bytes that deleting cannot free. And
/// a file that cannot be read cannot be judged, so it leaves the running
/// rather than joining a group by default.
final class DuplicatesTests: XCTestCase {

    private func file(_ path: String, bytes: Int, id: UInt64) -> FileFacts {
        FileFacts(path: path, bytes: bytes, fileID: id)
    }

    // MARK: - Size nominates

    func testOnlyEqualSizesAboveTheFloorAreCandidates() {
        let groups = Duplicates.sizeGroups([
            file("/a", bytes: 5_000_000, id: 1),
            file("/b", bytes: 5_000_000, id: 2),
            file("/c", bytes: 7_000_000, id: 3),          // alone in its size
            file("/d", bytes: 100, id: 4),                 // below the floor
            file("/e", bytes: 100, id: 5),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.path)), ["/a", "/b"])
    }

    /// One inode, two names: a hard link. Deleting one frees nothing, so the
    /// pair must never be offered as a duplicate.
    func testHardLinksAreOneFileNotTwo() {
        let groups = Duplicates.sizeGroups([
            file("/original", bytes: 5_000_000, id: 42),
            file("/hardlink", bytes: 5_000_000, id: 42),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        XCTAssertTrue(groups.isEmpty)
    }

    func testAHardLinkPairPlusARealCopyStillGroups() {
        let groups = Duplicates.sizeGroups([
            file("/original", bytes: 5_000_000, id: 42),
            file("/hardlink", bytes: 5_000_000, id: 42),
            file("/realcopy", bytes: 5_000_000, id: 7),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        // One of the linked pair stays to represent the inode; the copy joins it.
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
        XCTAssertTrue(groups[0].contains { $0.path == "/realcopy" })
    }

    // MARK: - Content decides

    func testSameSizeDifferentContentIsNotADuplicate() {
        let facts = [file("/a", bytes: 5_000_000, id: 1),
                     file("/b", bytes: 5_000_000, id: 2)]
        XCTAssertTrue(Duplicates.refine(facts, by: { $0.path == "/a" ? "aaaa" : "bbbb" }).isEmpty)
    }

    /// The partial hash exists to be cheap, not to be right: two files that
    /// begin alike but end differently must be split by the full hash.
    func testSamePrefixDifferentTailIsSplitByTheFullHash() {
        let facts = [file("/a", bytes: 5_000_000, id: 1),
                     file("/b", bytes: 5_000_000, id: 2)]
        let byPrefix = Duplicates.refine(facts, by: { _ in "same-prefix" })
        XCTAssertEqual(byPrefix.count, 1, "the cheap check agrees, so the full hash is asked")
        XCTAssertTrue(byPrefix.flatMap { Duplicates.refine($0, by: { $0.path == "/a" ? "AAAA" : "BBBB" }) }.isEmpty)
    }

    func testTrueDuplicatesGroupWithWastedBytes() {
        let identical = [file("/a", bytes: 5_000_000, id: 1),
                         file("/b", bytes: 5_000_000, id: 2),
                         file("/c", bytes: 5_000_000, id: 3)]
        let group = Duplicates.group(identical, by: KeepRule(.standard))
        XCTAssertEqual(group.paths.count, 3)
        XCTAssertEqual(group.bytes, 5_000_000)
        // Keeping one costs nothing; the waste is every copy beyond it.
        XCTAssertEqual(group.wasted, 10_000_000)
    }

    /// Unreadable is unknown, and unknown must not join a group: reporting a
    /// file as "identical" without having read it is a guess wearing a fact's
    /// clothing.
    func testAnUnreadableFileLeavesTheRunning() {
        let facts = [file("/a", bytes: 5_000_000, id: 1),
                     file("/b", bytes: 5_000_000, id: 2),
                     file("/locked", bytes: 5_000_000, id: 3)]
        let groups = Duplicates.refine(facts, by: { $0.path == "/locked" ? nil : "p" })
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.path)), ["/a", "/b"])
    }

    func testPathsInsideAGroupAreSortedForStableDisplay() {
        let group = Duplicates.group([file("/z", bytes: 5_000_000, id: 1),
                                      file("/a", bytes: 5_000_000, id: 2)], by: KeepRule(.standard))
        XCTAssertEqual(group.paths, ["/a", "/z"])
    }
}

extension DuplicatesTests {
    /// fileID 0 is "could not stat", and unknown is not "the same file":
    /// collapsing unknowns as if hard-linked hid real duplicates behind a
    /// stat failure.
    func testUnknownInodesAreNeverCollapsed() {
        let groups = Duplicates.sizeGroups([
            FileFacts(path: "/a", bytes: 5_000_000, fileID: 0),
            FileFacts(path: "/b", bytes: 5_000_000, fileID: 0),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].count, 2)
    }
}
