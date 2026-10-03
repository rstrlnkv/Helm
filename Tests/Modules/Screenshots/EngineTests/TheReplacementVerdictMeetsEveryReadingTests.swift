import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Screenshots_Engine

/// **The verdict is the one question the replacement of a file stands on, so it is asked of every shape a reading can
/// take.** `ShotReplacement.verdict(stored:now:)` says whether what is at the path is still the file the shot wrote:
/// the same device and inode, the same size, the same modification time to the nanosecond, a plain file on both sides.
/// A field the comparison forgets is a way to move a stranger's file to the Trash, and each field is asked **alone**:
/// a check that changed everything at once would stay green with any one comparison taken out.
///
/// Total failure of the subject prints: `.same` for a file that was written into, swapped for a copy of itself, turned
/// into a link or a folder, or read from nowhere.
final class TheReplacementVerdictMeetsEveryReadingTests: XCTestCase {

    private func reading(device: UInt64 = 1, inode: UInt64 = 2, size: Int64 = 3, seconds: Int64 = 4, nanoseconds: Int64 = 5,
                         regular: Bool = true) -> ShotReading {
        ShotReading(identity: PathCanonical.FileIdentity(device: device, inode: inode), size: size, modifiedSeconds: seconds,
                    modifiedNanoseconds: nanoseconds, isRegularFile: regular)
    }

    private func verdict(_ now: ShotReading?, stored: ShotReading? = nil) -> ShotReplacement.Verdict {
        ShotReplacement.verdict(stored: stored ?? reading(), now: now)
    }

    // MARK: The same, and every one thing that is not

    func testTheSameReadingIsTheSameFile() {
        XCTAssertEqual(verdict(reading()), .same)
    }

    /// Each field alone, the other four as they were stored: this is the test that goes red for one comparison taken out.
    func testEveryFieldAloneIsAnotherFile() {
        let cases: [(String, ShotReading)] = [
            ("device", reading(device: 9)),
            ("inode", reading(inode: 9)),
            ("size", reading(size: 4)),
            ("seconds", reading(seconds: 5)),
            ("nanoseconds", reading(nanoseconds: 6)),
            ("kind", reading(regular: false)),
        ]
        for (field, now) in cases {
            XCTAssertEqual(verdict(now), .changed, "only the \(field) differs and the file was taken for the same")
        }
    }

    func testEveryFieldTogetherIsAnotherFile() {
        XCTAssertEqual(verdict(reading(device: 9, inode: 9, size: 9, seconds: 9, nanoseconds: 9, regular: false)), .changed)
        XCTAssertEqual(verdict(reading(device: 9, inode: 9, size: 9, seconds: 9, nanoseconds: 9)), .changed)
    }

    /// A device and an inode that trade places are not the same pair, and a pair compared as a sum would not tell.
    func testDeviceAndInodeAreNotInterchangeable() {
        XCTAssertEqual(verdict(reading(device: 2, inode: 1), stored: reading(device: 1, inode: 2)), .changed)
        XCTAssertEqual(verdict(reading(device: 3, inode: 0), stored: reading(device: 0, inode: 3)), .changed)
        XCTAssertEqual(verdict(reading(device: 1, inode: 3), stored: reading(device: 2, inode: 2)), .changed, "the pair was added up")
    }

    // MARK: The time is two integers, never one number

    func testOneNanosecondIsAnotherWriting() {
        XCTAssertEqual(verdict(reading(nanoseconds: 6)), .changed)
        XCTAssertEqual(verdict(reading(nanoseconds: 4)), .changed)
        XCTAssertEqual(verdict(reading(seconds: 4, nanoseconds: 999_999_999),
                               stored: reading(seconds: 4, nanoseconds: 999_999_998)), .changed)
    }

    /// A second and a billion nanoseconds are one instant added up and two readings as `stat` gives them.
    func testTheTwoHalvesOfTheTimeAreNotAddedUp() {
        XCTAssertEqual(verdict(reading(seconds: 5, nanoseconds: 0), stored: reading(seconds: 4, nanoseconds: 1_000_000_000)), .changed)
        XCTAssertEqual(verdict(reading(seconds: 4, nanoseconds: 1), stored: reading(seconds: 5, nanoseconds: 0)), .changed)
        XCTAssertEqual(verdict(reading(seconds: 4, nanoseconds: 5), stored: reading(seconds: 4, nanoseconds: 5)), .same)
    }

    func testATimeBeforeTheEpochAndAtItsLargestIsReadAsItIs() {
        for seconds in [Int64.min, -1, 0, Int64.max] {
            for nanoseconds in [Int64(0), 999_999_999, Int64.max] {
                let stored = reading(seconds: seconds, nanoseconds: nanoseconds)
                XCTAssertEqual(verdict(stored, stored: stored), .same, "\(seconds).\(nanoseconds)")
                XCTAssertEqual(verdict(reading(seconds: seconds, nanoseconds: nanoseconds == 0 ? 1 : nanoseconds - 1), stored: stored), .changed)
            }
        }
    }

    // MARK: Sizes at the edges

    func testSizesAtTheEdges() {
        for size in [Int64(0), 1, 4096, Int64.max] {
            let stored = reading(size: size)
            XCTAssertEqual(verdict(reading(size: size), stored: stored), .same, "size \(size)")
            XCTAssertEqual(verdict(reading(size: size == Int64.max ? size - 1 : size + 1), stored: stored), .changed,
                           "size \(size) plus or minus one was taken for the same")
        }
        XCTAssertEqual(verdict(reading(size: 0), stored: reading(size: Int64.max)), .changed)
        XCTAssertEqual(verdict(reading(size: -1), stored: reading(size: 3)), .changed)
    }

    // MARK: Nothing, and what is not a plain file

    func testNothingAtThePathIsMissingWhateverWasStored() {
        XCTAssertEqual(verdict(nil), .missing)
        XCTAssertEqual(verdict(nil, stored: reading(regular: false)), .missing)
    }

    /// A stored reading of a link or a folder is of nothing this module wrote: even the same reading again is refused.
    func testAReadingThatIsNotAPlainFileIsNeverTheSame() {
        let link = reading(regular: false)
        XCTAssertEqual(verdict(link, stored: link), .changed, "a link was taken for the file written")
        XCTAssertEqual(verdict(reading(), stored: link), .changed, "a plain file was taken for the link that was stored")
    }

    // MARK: Read off real files

    private func lstatReading(_ url: URL) -> ShotReading? { FileShotWriter().reading(of: url) }

    func testRealFilesRealLinksRealFoldersAndNothing() throws {
        let folder = scratchDirectory("verdict-real")
        let file = folder.appendingPathComponent("a.png")
        try Data(repeating: 7, count: 100).write(to: file)
        let stored = try XCTUnwrap(lstatReading(file))
        XCTAssertTrue(stored.isRegularFile)
        XCTAssertEqual(stored.size, 100)
        XCTAssertEqual(verdict(lstatReading(file), stored: stored), .same)

        let link = folder.appendingPathComponent("link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let linkReading = try XCTUnwrap(lstatReading(link))
        XCTAssertFalse(linkReading.isRegularFile, "lstat of a link must answer for the link and not for its target")
        XCTAssertNotEqual(linkReading.identity, stored.identity)
        XCTAssertEqual(verdict(linkReading, stored: stored), .changed)

        let sub = folder.appendingPathComponent("dir.png", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: false)
        let dir = try XCTUnwrap(lstatReading(sub))
        XCTAssertFalse(dir.isRegularFile)
        XCTAssertEqual(verdict(dir, stored: stored), .changed)

        XCTAssertNil(lstatReading(folder.appendingPathComponent("nothing.png")))
        XCTAssertEqual(verdict(lstatReading(folder.appendingPathComponent("nothing.png")), stored: stored), .missing)
        // A folder above it that is not a folder at all: every reason there is nothing to read is the same nil.
        XCTAssertNil(lstatReading(file.appendingPathComponent("below.png")))
    }

    /// The time is read to the nanosecond off a real file, and a write of one byte in place moves only size and time.
    func testAWriteInPlaceKeepsTheInodeAndMovesSizeAndTime() throws {
        let folder = scratchDirectory("verdict-inplace")
        let file = folder.appendingPathComponent("a.png")
        try Data(repeating: 7, count: 10).write(to: file)
        let stored = try XCTUnwrap(lstatReading(file))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1]))
        try handle.close()
        let now = try XCTUnwrap(lstatReading(file))
        XCTAssertEqual(now.identity, stored.identity, "the control: written in place, the inode is the same")
        XCTAssertEqual(verdict(now, stored: stored), .changed)
    }

    /// `stat`'s own fields reach the reading as they are: a device number below zero (which `dev_t` can hold) neither
    /// traps nor differs between two readings of the same thing.
    func testAStatWithANegativeDeviceIsReadWithoutTrapping() {
        var info = stat()
        info.st_dev = -5
        info.st_ino = 77
        info.st_size = 12
        info.st_mode = S_IFREG | 0o644
        info.st_mtimespec = timespec(tv_sec: 1_790_000_000, tv_nsec: 123_456_789)
        let first = ShotReading(info), second = ShotReading(info)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identity.device, UInt64(bitPattern: Int64(-5)))
        XCTAssertEqual(first.modifiedSeconds, 1_790_000_000)
        XCTAssertEqual(first.modifiedNanoseconds, 123_456_789)
        XCTAssertTrue(first.isRegularFile)
        info.st_mode = S_IFLNK | 0o755
        XCTAssertFalse(ShotReading(info).isRegularFile)
        info.st_mode = S_IFDIR | 0o755
        XCTAssertFalse(ShotReading(info).isRegularFile)
        // A device node or a socket has a mode that contains the regular-file bits only in the wrong place.
        info.st_mode = S_IFBLK | 0o644
        XCTAssertFalse(ShotReading(info).isRegularFile)
        info.st_mode = S_IFSOCK | 0o644
        XCTAssertFalse(ShotReading(info).isRegularFile)
    }
}
