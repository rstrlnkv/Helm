import Foundation
import XCTest
@testable import Module_Disk_Engine

/// The paths the UI receives, pinned against the paths the scan was fed.
///
/// `DiskNode` used to carry the full path beside the name on every node, which
/// on a 1.5M-node tree measured 437.6 MB against 92 MB for the name alone. The
/// path is now composed during the traversals that need it — the snapshot, the
/// advisor, the ring — so the string a person sees, and the string that reaches
/// `RemovableScope` when they trash a row, is built rather than stored.
///
/// That makes path composition a correctness question and not a formatting one.
/// These tests say nothing about *how* the path is obtained: they feed known
/// paths in and require the same strings back out, so they held before the
/// storage was removed and have to hold after.
final class DerivedPathTests: XCTestCase {

    /// Every path in the transported tree, in traversal order, duplicates kept.
    /// A set would hide the one collision that matters — see the bucket test.
    private func paths(of entry: DiskEntry) -> [String] {
        [entry.path] + entry.children.flatMap(paths(of:))
    }

    // MARK: - The field itself

    /// The saving is a stored field that is not there, so this asserts on the
    /// shape of the node rather than on a measurement.
    ///
    /// `ScanFootprintTests` cannot do it: its ceiling is 2000 bytes per file,
    /// deliberately loose because a real home directory differs machine to
    /// machine, and it guards an order-of-magnitude defect in the walk's
    /// autoreleasepool. Putting the path back measured 597 bytes per file
    /// against 442–457 without it on this machine — a difference far too small
    /// for that ceiling to notice, and far too machine-dependent to assert.
    /// Whether the field exists is neither.
    func testANodeStoresNoPath() {
        let mirror = Mirror(reflecting: DiskNode(name: "x", bytes: 1, isDirectory: false))
        let labels = mirror.children.compactMap(\.label)

        XCTAssertFalse(labels.contains("path"), """
            DiskNode is storing a path again. It holds \(labels).
            A full path per node cost 155 bytes per file walked here (597 against \
            442) and scales with the node count, not the file count: on a 1.5M-node \
            volume the pair measured 437.6 MB against 92 MB for the name alone. \
            Compose the path in the traversal that needs it, as the snapshot, \
            DiskAdvisor and RingLayout do.
            """)
        XCTAssertTrue(labels.contains("name"), "the name is what a path is composed from")
    }

    // MARK: - The volume root

    /// `/` is the case `ScanPath` was written for: joining a child onto it with
    /// a plain `+ "/" +` yields `//Users`, and every descendant inherits the
    /// doubled slash until comparisons against absolute paths stop matching.
    /// Composing paths on the way down is exactly where that mistake gets made
    /// again, so the root of a real volume is the first thing pinned.
    func testScanningTheVolumeRootProducesNoDoubledSlash() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1_000)
        builder.addFile(path: "/Users/ann/фильм.mkv", bytes: 2_000_000, fileID: 1)
        builder.addFile(path: "/private/var/db/big.dat", bytes: 3_000_000, fileID: 2)

        let all = paths(of: DiskEntry(builder.build(), depth: 6, path: "/"))

        XCTAssertEqual(all.filter { $0.contains("//") }, [],
                       "a doubled slash reached the wire: \(all)")
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

    /// The bucket is invented, so its path is composed from a name a person can
    /// also type. `DiskEntry.id` depends on that: it disambiguates the bucket
    /// from a real file called `…` by appending a NUL, which is only needed
    /// *because* the two paths are equal. If composition ever gave the bucket a
    /// different string, the collision would disappear and so would the reason
    /// for the NUL — quietly, with `FoldedBucketWireTests` still green.
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

    /// The bucket directly inside a volume root, which is where the two rules
    /// above meet: the parent path already ends in `/`, so this is the one place
    /// the tree composes a path against a trailing slash. It is also the case
    /// that makes the rest of this suite bite — the other paths are strings the
    /// scan was handed, and only this one is arithmetic.
    func testTheBucketAtTheVolumeRootDoesNotDoubleTheSlash() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1_000)
        builder.addFile(path: "/tiny.txt", bytes: 10, fileID: 1)

        let all = paths(of: DiskEntry(builder.build(), depth: 6, path: "/"))

        XCTAssertEqual(all.sorted(), ["/", "/…"],
                       "the bucket beside a volume root: \(all)")
    }
}
