import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// A path the walk composed has to name the file the walk found.
///
/// `DiskNode` holds the name, not the path, so every path is composed after the
/// fact with `ScanPath.child(of:name:)` in three descents (`DiskEntry`'s
/// snapshot, `DiskAdvisor`'s sweep, `RingLayout`). That string is what a click
/// puts in the basket, what `UserFileScope` judges and what
/// `FileManager.trashItem` is handed, so a name the composition does not
/// survive is a row whose path is not the file it is drawn over.
///
/// `AdversarialInputTests` asks this of `TreeBuilder` with written paths; this
/// asks it of a real walk, where the names come out of `getattrlistbulk` as
/// bytes through `String(cString:)`.
///
/// The folded bucket is excluded by its flag, never by its name `…`.
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

    /// A file somebody really named `…`, the name the scan gives its folded
    /// bucket, is the person's own file to the gate. The bucket is told apart
    /// by `isFolded`, which cannot be typed into a filename, so the gate has no
    /// reason to refuse a path ending in `/…`.
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

    /// The walk's own aggregate and a person's file of the same name side by side.
    /// The order the files arrive in is the filesystem's, so the builder is fed
    /// the real file first by hand: the small file after it must fold into a
    /// bucket of its own, and the entry composed for the real file must still be
    /// the file on disk, at its own weight.
    func testASmallFileFoldsIntoTheBucketAndNotIntoARealFileNamedLikeIt() throws {
        let root = scratchDirectory("disk-bucket-name")
        XCTAssertTrue(FileManager.default.createFile(atPath: root.path + "/…",
                                                     contents: Data(repeating: 0x41,
                                                                    count: 40_000)))
        let builder = TreeBuilder(root: root.path, foldThreshold: 1_000)
        builder.addFile(path: root.path + "/…", bytes: 40_000, fileID: 1)
        builder.addFile(path: root.path + "/tiny.bin", bytes: 10, fileID: 2)
        let snapshot = DiskEntry(builder.build(), depth: 2, path: root.path)

        let real = try XCTUnwrap(snapshot.children.first { !$0.isFolded },
                                 "the person's file stopped being its own entry")
        XCTAssertEqual(real.bytes, 40_000,
                       "the small file was charged to the person's file named like the bucket")
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.path))
        XCTAssertEqual(snapshot.children.filter(\.isFolded).count, 1,
                       "the small file did not land in a bucket of its own")
    }

    /// And the count the header reports is the number of files there are — a
    /// name that broke the walk would show up here as a file that was never
    /// counted rather than as a crash.
    func testTheCountIsEveryFileTheFixtureMade() throws {
        let root = try makeFixture()
        let box = Locked<ScanTick?>(nil)
        _ = DiskScanner(foldThreshold: 0).scan(root: root.path, onProgress: { box.value = $0 })
        let last = try XCTUnwrap(box.value)
        XCTAssertEqual(last.files, Self.hostileNames.count + 1)
    }

    /// A directory handed over with a trailing slash joins with one slash, not
    /// two.
    func testTrailingSlashIsNotDoubled() {
        XCTAssertEqual(ScanPath.child(of: "/Users/me/", name: "Downloads"),
                       "/Users/me/Downloads")
    }
}
