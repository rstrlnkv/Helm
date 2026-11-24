import XCTest
@testable import Module_Duplicates_Engine

/// A file whose identity could not be read is unknown, and unknown must never
/// match — the rule `BulkWalk.DeviceID.unknown` already lives by.
///
/// The trap: fileID 0 is the "could not be read" sentinel, and
/// `Duplicates.sizeGroups` collapses equal `fileID`s as "one file wearing two
/// names". Two *different* files that both failed `lstat` would be collapsed
/// into one and silently dropped from the search, and a collapse keyed on the
/// id alone, across sizes, would let a 5 MB unknown swallow a 7 MB unknown
/// with a genuine twin. The walk stays on one device, but the logic must hold
/// on its own: whoever feeds it a 0 must not lose a file for it.
///
/// (The cross-volume sibling is not pinned here because a test cannot
/// conjure a second filesystem: an id carries no device, so two files on
/// different volumes sharing an inode *number* would collapse the same way
/// if the walk left the root's volume — see `DeviceIDTests`.)
final class DuplicateIdentityTests: XCTestCase {

    /// Two distinct files whose id the walk did not return both arrive with
    /// fileID 0. They are not hard links of each other — nothing is known about
    /// them — so they must stay in the running as separate candidates.
    func testTwoUnknownIdentitiesAreNotCollapsedAsHardLinks() {
        let groups = Duplicates.sizeGroups([
            fileWithID("/a", bytes: 5_000_000, id: 0),
            fileWithID("/b", bytes: 5_000_000, id: 0),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        XCTAssertEqual(groups.count, 1,
                       "two files of unknown identity were collapsed into one — "
                       + "fileID 0 means unread, not hard-linked")
        XCTAssertEqual(Set(groups.first?.map(\.path) ?? []), ["/a", "/b"])
    }

    /// An unknown of one size must not swallow an unknown of another — sizes a
    /// hard link could never disagree on — or the 7 MB file with a genuine twin
    /// vanishes because a 5 MB stranger claimed id 0 first.
    func testAnUnknownIdentityDoesNotSwallowAFileOfAnotherSize() {
        let groups = Duplicates.sizeGroups([
            fileWithID("/small-unknown", bytes: 5_000_000, id: 0),
            fileWithID("/big-unknown", bytes: 7_000_000, id: 0),
            fileWithID("/big-twin", bytes: 7_000_000, id: 9),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        XCTAssertEqual(groups.count, 1,
                       "the 7 MB candidate pair is gone — a 5 MB file with the "
                       + "same sentinel id absorbed it")
        XCTAssertEqual(Set(groups.first?.map(\.path) ?? []),
                       ["/big-unknown", "/big-twin"])
    }

    /// The honest hard-link collapse holds: one real inode, two names, still
    /// one file.
    func testRealHardLinksStayCollapsed() {
        let groups = Duplicates.sizeGroups([
            fileWithID("/original", bytes: 5_000_000, id: 42),
            fileWithID("/hardlink", bytes: 5_000_000, id: 42),
        ], minBytes: 1_000_000, by: KeepRule(.standard))
        XCTAssertTrue(groups.isEmpty)
    }
}
