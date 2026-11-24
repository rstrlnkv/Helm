import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The walk three modules share, and the facts each of them needs out of it.
///
/// Each caller needs something different, so the walk carries all of it: the
/// clone-and-hard-link ledger reads `linkCount` and the file id, the duplicate
/// finder the logical size and the date a copy arrived, Disk the allocated size
/// and the device (Architecture/ModulePattern.md § Bulk reads).
final class BulkWalkTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("bulk-walk")
    }

    // MARK: - What one directory answers

    func testAFileCarriesItsSizesItsIdAndItsLinkCount() throws {
        try write("payload.bin", in: root, bytes: 300_000)

        let entries = try XCTUnwrap(BulkWalk.children(of: root.path))
        let file = try XCTUnwrap(entries.first { $0.path.hasSuffix("payload.bin") })

        XCTAssertFalse(file.isDirectory)
        XCTAssertTrue(file.isRegularFile)
        XCTAssertEqual(file.logicalBytes, 300_000)
        XCTAssertGreaterThanOrEqual(file.allocatedBytes, 300_000)
        XCTAssertEqual(file.linkCount, 1)

        // Against the kernel's own answer, so the parse is checked rather than
        // trusted: a misread field is a plausible-looking number.
        var status = stat()
        XCTAssertEqual(lstat(file.path, &status), 0)
        XCTAssertEqual(file.fileID, status.st_ino)
        XCTAssertEqual(file.modified, TimeInterval(status.st_mtimespec.tv_sec)
                       + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000,
                       accuracy: 0.000_001)
    }

    /// The ledger's raw material: `FileWeight` charges one allocation once
    /// however many names it wears, deciding from the link count which entries
    /// can collide, so a link count of 1 for every file would silently skew
    /// every size in the app.
    func testTwoNamesForOneAllocationAgreeOnTheirIdAndSayThereAreTwo() throws {
        let payload = try write("payload.bin", in: root, bytes: 300_000)
        try FileManager.default.linkItem(at: payload,
                                         to: root.appendingPathComponent("alias.bin"))

        let entries = try XCTUnwrap(BulkWalk.children(of: root.path))
        let names = entries.filter { !$0.isDirectory }
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(Set(names.map(\.fileID)).count, 1, "two names, one inode")
        XCTAssertEqual(names.map(\.linkCount), [2, 2])
    }

    /// The date the copy arrived, not the date it was made: the duplicate
    /// finder picks the copy that stays by Finder's «Date Added», which a file
    /// does not carry when copied.
    ///
    /// Compared exactly, over twenty files: a `Date` composed in the wrong
    /// order of arithmetic lands some nanoseconds away from what Foundation
    /// reports, in a fraction of readings, and a tolerance would call that
    /// agreement.
    func testEveryFileCarriesTheDateItArrivedWithNothingLostInTheArithmetic() throws {
        for index in 0..<20 { try write("f\(index).bin", in: root, bytes: 1000) }

        let entries = try XCTUnwrap(BulkWalk.children(of: root.path))
        XCTAssertEqual(entries.count, 20)

        for entry in entries {
            let expected = try URL(fileURLWithPath: entry.path)
                .resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate
            try XCTSkipIf(expected == nil, "this volume does not record when a file was added")
            XCTAssertEqual(entry.added, expected, entry.path)
        }
    }

    /// A symlink is neither descended nor sized: its target belongs to whoever
    /// owns it. `FileManager`'s enumerator yields the link with 0 allocated
    /// bytes, so dropping it changes no total.
    func testASymlinkIsNotYielded() throws {
        try write("real.bin", in: root, bytes: 300_000)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.bin"),
            withDestinationURL: root.appendingPathComponent("real.bin"))

        let entries = try XCTUnwrap(BulkWalk.children(of: root.path))
        XCTAssertEqual(entries.map { ($0.path as NSString).lastPathComponent }, ["real.bin"])
    }

    /// A directory that would not open is never an empty one: every TCC
    /// refusal arrives this way, and "no entries" would draw a false zero.
    func testADirectoryThatWillNotOpenAnswersNothingRatherThanNoEntries() throws {
        let closed = root.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try write("closed/inside.bin", in: root, bytes: 1000)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: closed.path)
        }

        XCTAssertNil(BulkWalk.children(of: closed.path))
    }

    // MARK: - The walk

    func testTheWalkReachesEveryFileBelowTheRoot() throws {
        for level in ["a", "a/b", "a/b/c"] {
            try write("\(level)/file.bin", in: root, bytes: 1000)
        }

        var found: [String] = []
        BulkWalk.walk(root: root.path) { batch in found += batch.files.map(\.path) }

        XCTAssertEqual(found.count, 3, "found \(found)")
    }

    /// The refusal every caller builds its own gate out of — the firmlink twin,
    /// the other volume, `~/Library` on the timer's path. It has to prune the
    /// subtree, not merely drop the directory.
    func testADirectoryTheCallerRefusesIsNotDescended() throws {
        try write("keep/file.bin", in: root, bytes: 1000)
        try write("Library/Caches/deep/file.bin", in: root, bytes: 1000)

        var found: [String] = []
        BulkWalk.walk(root: root.path,
                      descends: { entry in
                          (entry.path as NSString).lastPathComponent != "Library"
                      },
                      consume: { batch in found += batch.files.map(\.path) })

        XCTAssertEqual(found.count, 1, "found \(found)")
        XCTAssertTrue(found[0].hasSuffix("keep/file.bin"), found[0])
    }

    /// One spelling out of the walk: an enumerator given `/var/folders/…` hands
    /// back children spelled `/private/var/folders/…`, so a gate comparing them
    /// against the root matches nothing and fails open. This walk composes
    /// every path from the root it was handed.
    func testEveryPathCarriesTheSpellingOfTheRootItWasGiven() throws {
        try write("deep/inside/file.bin", in: root, bytes: 1000)

        // Both spellings of the same directory; under `/Users` there is one.
        var spellings = [root.path]
        let plain = PathCanonical.withoutPrivate(root.path)
        if plain != root.path {
            spellings.append(plain)
        } else if FileManager.default.fileExists(atPath: "/private" + root.path) {
            spellings.append("/private" + root.path)
        }
        XCTAssertEqual(spellings.count, 2, "the fixture has only one spelling: \(spellings)")

        for spelling in spellings {
            var paths: [String] = []
            BulkWalk.walk(root: spelling) { batch in paths += batch.files.map(\.path) }
            XCTAssertFalse(paths.isEmpty, "nothing walked under \(spelling)")
            for path in paths {
                XCTAssertTrue(path.hasPrefix(spelling + "/"),
                              "\(path) does not carry the spelling of \(spelling)")
            }
        }
    }

    /// A denied directory reaches the caller by name, because Disk draws it as
    /// «No access» rather than as a folder holding nothing.
    func testADeniedDirectoryIsReportedToTheCaller() throws {
        let closed = root.appendingPathComponent("closed")
        try FileManager.default.createDirectory(at: closed, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: closed.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                   ofItemAtPath: closed.path)
        }

        var denied: [String] = []
        BulkWalk.walk(root: root.path) { batch in denied += batch.denied }

        XCTAssertEqual(denied, [closed.path])
    }

    /// Asked before the first directory is opened, so the assertion is about
    /// files not read rather than a flag handed back: a walk that ignored the
    /// question and read the whole tree would still say "cancelled".
    func testAWalkCancelledBeforeItBeginsReadsNothingAndSaysSo() throws {
        for index in 0..<8 { try write("d\(index)/file.bin", in: root, bytes: 1000) }

        var found: [String] = []
        let completed = BulkWalk.walk(root: root.path, isCancelled: { true },
                                      consume: { batch in found += batch.files.map(\.path) })

        XCTAssertTrue(found.isEmpty, "a cancelled walk read \(found.count) files")
        XCTAssertFalse(completed, "a cancelled walk reported itself finished")
    }

    /// And a walk stopped part way through says the same, so a caller that must
    /// not report a partial answer — «what is duplicated» is a whole answer or
    /// none — can tell one from the other.
    func testAWalkStoppedPartWayThroughIsNotReportedAsFinished() throws {
        for index in 0..<40 { try write("d\(index)/file.bin", in: root, bytes: 1000) }

        let stop = Locked(false)
        let completed = BulkWalk.walk(root: root.path, isCancelled: { stop.value },
                                      consume: { _ in stop.value = true })

        XCTAssertFalse(completed, "a cancelled walk reported itself finished")
    }

}
