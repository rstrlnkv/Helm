import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// A path the walk composed has to name the file the walk found.
///
/// `DiskNode` holds the **name**, not the path — a full path per node cost
/// ~345 MB on a large volume — so every path in this module is arithmetic
/// performed after the fact: `ScanPath.child(of:name:)`, on the way down, in
/// three separate descents (`DiskEntry`'s snapshot, `DiskAdvisor`'s sweep,
/// `RingLayout`). Those strings are not decoration. One of them is what a click
/// puts in the basket, what `UserFileScope` is asked to judge, and what
/// `FileManager.trashItem` is finally handed — so a name the arithmetic does not
/// survive is a row that deletes nothing, or worse, is a row whose path is not
/// the file it is drawn over.
///
/// `AdversarialInputTests` asks this of `TreeBuilder` with paths a test wrote
/// down. This asks it of a **real walk over real files**: the names come back out
/// of `getattrlistbulk` as bytes, through `String(cString:)`, and only then into
/// the composition. Nothing in the suite went that way round.
///
/// The one path here that is not a file is the folded bucket, and that is
/// deliberate: it is an aggregate the scan invents per directory wearing the
/// name `…`, which `isFolded` exists to tell apart from a real file with that
/// name. It is excluded by the flag, never by the name.
final class EveryComposedPathNamesItsFileTests: XCTestCase {

    /// Names a filesystem accepts and string handling does not.
    ///
    /// The newline is the sharpest of them — it is the separator the removal
    /// dialog lists paths with — and the trailing space, the leading dot and the
    /// colon are the three Finder itself treats specially. `…` is the folded
    /// bucket's own name, as a file somebody really made.
    private static let hostileNames = [
        "line\nbreak.bin",
        "tab\there.bin",
        "trailing space .bin",
        " leading space.bin",
        ".hidden.bin",
        "colon:name.bin",
        "percent %@ %d.bin",
        "quote\"and'apostrophe.bin",
        "кириллица.bin",
        "emoji 🙂👍🏽.bin",
        "…",
        String(repeating: "long", count: 50) + ".bin",
    ]

    /// Every composed path in the snapshot the UI receives, bucket excluded.
    private func paths(of entry: DiskEntry) -> [String] {
        (entry.isFolded ? [] : [entry.path]) + entry.children.flatMap(paths(of:))
    }

    private func makeFixture() throws -> URL {
        let root = scratchDirectory("disk-hostile-names")
        for name in Self.hostileNames {
            // Written through the path rather than `appendingPathComponent`, so
            // the bytes on disk are the bytes in the array above.
            let path = root.path + "/" + name
            XCTAssertTrue(FileManager.default.createFile(atPath: path,
                                                         contents: Data(repeating: 0x41,
                                                                        count: 40_000)),
                          "the fixture could not make \(name.debugDescription)")
        }
        // And once more one level down, under a directory whose own name is
        // hostile: the composition is per level, so a name that survives at the
        // leaf can still be lost as an ancestor.
        let inner = root.path + "/dir with\nnewline"
        try FileManager.default.createDirectory(atPath: inner,
                                                withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: inner + "/кириллица 🙂.bin",
                                                     contents: Data(repeating: 0x41,
                                                                    count: 40_000)))
        return root
    }

    func testEveryPathTheSnapshotCarriesIsAFileThatIsReallyThere() throws {
        let root = try makeFixture()
        // Nothing folds: the fold threshold is what turns small files into an
        // aggregate, and this test is about the names of real ones.
        let tree = try XCTUnwrap(DiskScanner(foldThreshold: 0).scan(root: root.path))
        let snapshot = DiskEntry(tree, depth: 6, path: root.path)

        let composed = paths(of: snapshot)
        // Said out loud: a walk that found nothing would satisfy every assertion
        // below by having nothing to check.
        XCTAssertEqual(composed.count, Self.hostileNames.count + 3,
                       "the walk did not find every file the fixture made: \(composed)")
        for path in composed {
            XCTAssertTrue(FileManager.default.fileExists(atPath: path),
                          "the walk composed a path that names nothing: \(path.debugDescription)")
        }
    }

    /// The other half, and the one that decides whether a row can be acted on:
    /// the gate has to recognise these paths as the user's own files. It
    /// standardizes and resolves before it judges, and a name it rewrites is a
    /// row that goes into the basket and is refused at the end.
    ///
    /// `…` is held out here and asked on its own below, because it fails for a
    /// different reason from any spelling accident.
    func testTheRemovalGateTakesEveryOneOfThoseNames() throws {
        let root = try makeFixture()
        let tree = try XCTUnwrap(DiskScanner(foldThreshold: 0).scan(root: root.path))
        let composed = paths(of: DiskEntry(tree, depth: 6, path: root.path))
            .filter { ($0 as NSString).lastPathComponent != "…" }
        XCTAssertEqual(composed.count, Self.hostileNames.count + 2,
                       "precondition: the walk found the files to judge")

        let (allowed, refused) = UserFileScope.partition(composed)
        XCTAssertEqual(allowed.count, composed.count,
                       "the gate refused paths of ordinary files: \(refused)")
    }

    /// A file somebody really named `…`, which is the name the scan gives its own
    /// folded bucket.
    ///
    /// `DiskNode.isFolded` was added because that collision cost the file three
    /// things: it absorbed every small file beside it, it showed a size that was
    /// not its own, and it **could not be selected, because `UserFileScope`
    /// refuses a path ending in `/…`**. The flag fixed the first two — the
    /// bucket is told apart by a flag now, which cannot be typed into a filename
    /// — and the third is untouched: the gate still judges by the name, so the
    /// row draws with its true size and the basket quietly declines it, with no
    /// sentence anywhere saying why. The same path arriving as one of a cache's
    /// contents comes back refused `outOfScope`, which is a reason about the
    /// app's rules rather than about this file.
    ///
    /// The bucket needs no such name test any more: it is `isFolded`, and the
    /// flag reaches the wire (`DiskEntry.isFolded`).
    func testAFileReallyNamedLikeTheFoldedBucketIsStillTheUsersOwnFile() throws {
        let root = try makeFixture()
        let tree = try XCTUnwrap(DiskScanner(foldThreshold: 0).scan(root: root.path))
        let snapshot = DiskEntry(tree, depth: 6, path: root.path)
        let ellipsis = try XCTUnwrap(snapshot.children.first { $0.name == "…" })

        XCTAssertFalse(ellipsis.isFolded,
                       "precondition: this is the person's file, not the scan's aggregate")
        XCTAssertTrue(FileManager.default.fileExists(atPath: ellipsis.path),
                      "precondition: the file is really there")

        XCTAssertTrue(UserFileScope.isRemovable(ellipsis.path), """
            a file the person made and can see on the ring cannot be put in the basket, and \
            nothing on screen says why: the gate refuses any path ending in `/…` because that \
            used to be the only way to recognise the scan's own folded bucket. The bucket \
            carries `isFolded` now.
            """)
    }

    /// And the count the header reports is the number of files there are — a
    /// name that broke the walk would show up here as a file that was never
    /// counted rather than as a crash.
    func testTheCountIsEveryFileTheFixtureMade() throws {
        let root = try makeFixture()
        final class Box: @unchecked Sendable { var last: ScanProgress? }
        let box = Box()
        _ = DiskScanner(foldThreshold: 0).scan(root: root.path, onProgress: { box.last = $0 })
        let last = try XCTUnwrap(box.last)
        XCTAssertEqual(last.filesSeen, Self.hostileNames.count + 1)
    }
}
