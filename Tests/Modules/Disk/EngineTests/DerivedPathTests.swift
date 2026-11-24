import Foundation
import XCTest
@testable import Module_Disk_Engine

/// The paths the UI receives, pinned against the paths the scan was fed.
///
/// `DiskNode` stores the name alone; the path is composed in the traversals that
/// need it (the snapshot, the advisor, the ring), so the string a person sees,
/// and the one the removal gate judges, is built rather than stored. These tests
/// feed known paths in and require the same strings back out.
final class DerivedPathTests: XCTestCase {

    /// Every path in the tree, in traversal order, duplicates kept.
    /// A set would hide the one collision that matters — see the bucket test.
    private func paths(of entry: DiskEntry) -> [String] {
        [entry.path] + entry.children.flatMap(paths(of:))
    }

    // MARK: - The volume root

    /// `/` is the case `ScanPath` exists for: a plain `+ "/" +` yields
    /// `//Users`, and every descendant inherits the doubled slash until
    /// comparisons against absolute paths stop matching.
    func testScanningTheVolumeRootProducesNoDoubledSlash() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1_000)
        builder.addFile(path: "/Users/ann/фильм.mkv", bytes: 2_000_000, fileID: 1)
        builder.addFile(path: "/private/var/db/big.dat", bytes: 3_000_000, fileID: 2)

        let all = paths(of: DiskEntry(builder.build(), depth: 6, path: "/"))

        XCTAssertEqual(all.filter { $0.contains("//") }, [],
                       "a doubled slash reached the entry: \(all)")
        XCTAssertEqual(all.sorted(), [
            "/",
            "/Users",
            "/Users/ann",
            "/Users/ann/фильм.mkv",
            "/private",
            "/private/var",
            "/private/var/db",
            "/private/var/db/big.dat",
        ].sorted())
    }

    // MARK: - An ordinary root

    /// The directories between the root and a file are invented by the builder
    /// as it indexes them — nobody hands it `/r/a/b`. Their paths have to come
    /// out as if somebody had.
    func testDirectoriesTheScanInventedCarryTheirOwnPath() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1_000)
        builder.addFile(path: "/r/a/b/c/deep.bin", bytes: 5_000_000, fileID: 1)

        XCTAssertEqual(paths(of: DiskEntry(builder.build(), depth: 6, path: "/r")),
                       ["/r", "/r/a", "/r/a/b", "/r/a/b/c", "/r/a/b/c/deep.bin"])
    }

    /// Unicode, spaces and dots in a name are just bytes to path arithmetic, but
    /// they are what a real home directory is full of, and a composed path is
    /// where a stray `standardizingPath` or percent-encoding would show up.
    func testNamesThatAreNotAsciiSurviveComposition() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1_000)
        let awkward = "/r/Мои документы/v2.0 final (копия).tar.gz"
        builder.addFile(path: awkward, bytes: 4_000_000, fileID: 1)

        XCTAssertTrue(paths(of: DiskEntry(builder.build(), depth: 6, path: "/r")).contains(awkward),
                      "got \(paths(of: DiskEntry(builder.build(), depth: 6, path: "/r")))")
    }

    // MARK: - The folded bucket

    /// The bucket's path is composed from a name a person can also type, so it
    /// equals a real file called `…`; `DiskEntry.id` tells them apart by
    /// appending a NUL.
    func testTheInventedBucketGetsThePathARealFileOfThatNameWouldHave() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1_000)
        builder.addFile(path: "/r/…", bytes: 100_000, fileID: 1)   // a real file
        builder.addFile(path: "/r/tiny.txt", bytes: 10, fileID: 2) // folds into the bucket

        let all = paths(of: DiskEntry(builder.build(), depth: 6, path: "/r"))

        XCTAssertEqual(all.filter { $0 == "/r/…" }.count, 2,
                       "the real file and the bucket should both be at /r/… — got \(all)")
        XCTAssertFalse(all.contains("/r/tiny.txt"),
                       "a folded file has no row of its own: \(all)")
    }

    /// The bucket directly inside a volume root: the parent path already ends in
    /// `/`, the one place the tree composes a path against a trailing slash.
    func testTheBucketAtTheVolumeRootDoesNotDoubleTheSlash() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1_000)
        builder.addFile(path: "/tiny.txt", bytes: 10, fileID: 1)

        let all = paths(of: DiskEntry(builder.build(), depth: 6, path: "/"))

        XCTAssertEqual(all.sorted(), ["/", "/…"],
                       "the bucket beside a volume root: \(all)")
    }
}
