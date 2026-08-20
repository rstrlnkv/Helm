import Foundation
import HelmTestSupport
import XCTest
@testable import HelmRuntime

/// The walk three modules share, and the facts each of them needs out of it.
///
/// Disk had this walker to itself while `FileWeight` and the duplicate finder
/// enumerated the slow way — measured on this Mac, warm cache, compiled `-O`:
/// 0,79 s against 0,23 s over 105 000 files, and 3,5 s against 1,2 s for the
/// forty bundles the Uninstaller sizes on its first visit. What each caller
/// needs is different, so what the walk answers has to carry all of it: the
/// clone-and-hard-link ledger reads `linkCount` and the file id, the duplicate
/// finder reads the logical size and the date a copy arrived, Disk reads the
/// allocated size and the device.
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

    /// **The ledger's raw material.** `FileWeight` charges one allocation once
    /// however many names it wears, and it decides which entries can possibly
    /// collide from the link count — so a walk that answered 1 for every file
    /// would make every size in the app wrong in the same direction, silently.
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

    /// **The date the copy arrived, not the date it was made.** The duplicate
    /// finder decides which copy stays by Finder's «Date Added», which a file
    /// does not carry with it when it is copied — read the wrong field and the
    /// survivor is picked by a different rule from the one the person chose.
    ///
    /// Compared **exactly**, and over enough files to make that mean something:
    /// a `Date` composed from a 2026-sized number of seconds and left to subtract
    /// its own epoch afterwards lands 240 ns away from what Foundation reports
    /// for the same file, in about a quarter of readings. One file with a
    /// tolerance would have called that agreement; twenty without one is what
    /// caught it — through `TheScannerCarriesTheDateItReadTests` in Duplicates,
    /// two modules away, which is exactly how far a promise travels when it is
    /// not tested where it is made.
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
    /// owns it. Measured against `FileManager`, whose enumerator does yield the
    /// link and answers 0 allocated bytes for it — so dropping it here keeps
    /// every existing total exactly where it was.
    func testASymlinkIsNotYielded() throws {
        try write("real.bin", in: root, bytes: 300_000)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.bin"),
            withDestinationURL: root.appendingPathComponent("real.bin"))

        let entries = try XCTUnwrap(BulkWalk.children(of: root.path))
        XCTAssertEqual(entries.map { ($0.path as NSString).lastPathComponent }, ["real.bin"])
    }

    /// **A directory that would not open is never an empty one.** Every TCC
    /// refusal arrives this way, and answering "no entries" draws a genuine zero
    /// on a map whose whole job is where the space went.
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

    /// **One spelling out of the walk.** Measured 2026-08-20: an enumerator
    /// given a root spelled `/var/folders/…` hands back children spelled
    /// `/private/var/folders/…`, so a gate comparing a walk's paths against the
    /// root it was given matches nothing and fails open without a word. This
    /// walk composes every path from the root it was handed, and this is the
    /// test that says so — it is the reason a new walker must not reintroduce
    /// the two spellings.
    func testEveryPathCarriesTheSpellingOfTheRootItWasGiven() throws {
        try write("deep/inside/file.bin", in: root, bytes: 1000)

        // Both spellings of the same directory, where this machine's layout has
        // two — under `/Users` it has one, and that is luck about the volume
        // rather than anything the code does.
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

    /// Stop is pressed when a walk is at its longest — that is why it is
    /// pressed. Asked before the first directory is opened, so the assertion is
    /// about the files that were not read rather than about a flag being handed
    /// back: `!isCancelled()` at the end would say "cancelled" for a walk that
    /// had ignored the question entirely and read the whole tree first.
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

        let stop = Stopped()
        let completed = BulkWalk.walk(root: root.path, isCancelled: { stop.value },
                                      consume: { _ in stop.stop() })

        XCTAssertFalse(completed, "a cancelled walk reported itself finished")
    }

    private final class Stopped: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        var value: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        func stop() { lock.lock(); stopped = true; lock.unlock() }
    }
}
