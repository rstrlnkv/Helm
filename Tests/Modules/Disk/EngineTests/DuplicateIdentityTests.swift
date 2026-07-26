import XCTest
@testable import Module_Disk_Engine

/// A file whose identity could not be read is unknown, and unknown must never
/// match — the rule `DiskScanner.DeviceID.unknown` already lives by.
///
/// The trap: fileID 0 is the "could not be read" sentinel, and
/// `Duplicates.sizeGroups` collapses equal `fileID`s as "one file wearing two
/// names". As first shipped, two *different* files that both failed `lstat`
/// shared fileID 0 and were collapsed into one — silently removed from the
/// duplicate search, with no refusal and no report. Worse, the collapse was
/// keyed on the id alone, across all sizes, so a 5 MB unknown swallowed a
/// 7 MB unknown that had a genuine 7 MB twin. The scanner now skips files it
/// cannot stat and stays on one device, but the logic must hold on its own:
/// whoever feeds it a 0 must not lose a file for it.
///
/// (The cross-volume sibling is not pinned here because a test cannot
/// conjure a second filesystem: an id carries no device, so two files on
/// different volumes sharing an inode *number* would collapse the same way
/// if the walk ever left the root's volume again — `DeviceIDTests` is the
/// record of this exact family.)
final class DuplicateIdentityTests: XCTestCase {

    private func file(_ path: String, bytes: Int, id: UInt64) -> FileFacts {
        FileFacts(path: path, bytes: bytes, fileID: id)
    }

    /// Two distinct files whose lstat failed both arrive with fileID 0. They
    /// are not hard links of each other — nothing is known about them — so
    /// they must stay in the running as separate candidates.
    func testTwoUnknownIdentitiesAreNotCollapsedAsHardLinks() {
        let groups = Duplicates.sizeGroups([
            file("/a", bytes: 5_000_000, id: 0),
            file("/b", bytes: 5_000_000, id: 0),
        ], minBytes: 1_000_000)
        XCTAssertEqual(groups.count, 1,
                       "two files of unknown identity were collapsed into one — "
                       + "fileID 0 means unread, not hard-linked")
        XCTAssertEqual(Set(groups.first?.map(\.path) ?? []), ["/a", "/b"])
    }

    /// The collapse is keyed on the id across *all* sizes, so an unknown of
    /// one size can swallow an unknown of another — sizes a hard link could
    /// never disagree on. Here the 7 MB file with a genuine twin vanishes
    /// because a 5 MB stranger claimed id 0 first.
    func testAnUnknownIdentityDoesNotSwallowAFileOfAnotherSize() {
        let groups = Duplicates.sizeGroups([
            file("/small-unknown", bytes: 5_000_000, id: 0),
            file("/big-unknown", bytes: 7_000_000, id: 0),
            file("/big-twin", bytes: 7_000_000, id: 9),
        ], minBytes: 1_000_000)
        XCTAssertEqual(groups.count, 1,
                       "the 7 MB candidate pair is gone — a 5 MB file with the "
                       + "same sentinel id absorbed it")
        XCTAssertEqual(Set(groups.first?.map(\.path) ?? []),
                       ["/big-unknown", "/big-twin"])
    }

    /// The honest hard-link collapse must survive whatever fix lands: one
    /// real inode, two names, still one file.
    func testRealHardLinksStayCollapsed() {
        let groups = Duplicates.sizeGroups([
            file("/original", bytes: 5_000_000, id: 42),
            file("/hardlink", bytes: 5_000_000, id: 42),
        ], minBytes: 1_000_000)
        XCTAssertTrue(groups.isEmpty)
    }
}
