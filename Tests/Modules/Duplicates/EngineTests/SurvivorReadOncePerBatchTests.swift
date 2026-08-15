import XCTest
import HelmTestSupport
@testable import Module_Duplicates_Engine

/// One removal reads its survivor once, not once per copy.
///
/// `DuplicateVerification.verify` reads both sides of every pair in full, so a
/// group of N copies read the copy that *stays* N−1 times — tens of seconds of
/// re-hashing one unchanging file on a real video group. `Batch` memoises the
/// survivor's reading for the life of one removal and nothing longer; the copy
/// being removed is read from disk on every call, always, which is the
/// guarantee the module advertises.
///
/// The counter is the assertion: these tests inject the hash and count which
/// paths it was asked about, so "read once" is a fact about calls rather than a
/// timing a fast disk could fake.
final class SurvivorReadOncePerBatchTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = scratchDirectory("survivor-once")
    }

    @discardableResult
    private func write(_ name: String, _ contents: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    /// A hash that counts, and still answers what the real one would: the
    /// verdicts must stay right while the reads are being counted, or the test
    /// would bless a cache that broke the comparison.
    private final class CountingHash: @unchecked Sendable {
        private let lock = NSLock()
        private var counts: [String: Int] = [:]

        func hash(_ path: String, expecting: Int) -> String? {
            lock.lock(); counts[path, default: 0] += 1; lock.unlock()
            return DuplicateScanner.hash(path, limit: nil, expecting: expecting)
        }

        func reads(of path: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            return counts[path] ?? 0
        }
    }

    func testTheSurvivorIsHashedOncePerBatch() throws {
        let keep = try write("keep.bin", "the same bytes")
        let removes = try (0..<3).map { try write("copy\($0).bin", "the same bytes") }
        let counting = CountingHash()
        let batch = DuplicateVerification.Batch(hash: counting.hash)

        let verdicts = removes.map { batch.verify(remove: $0, keep: keep) }

        XCTAssertEqual(verdicts, [.identical, .identical, .identical])
        XCTAssertEqual(counting.reads(of: keep), 1,
                       "the survivor was re-read once per copy")
        for remove in removes {
            XCTAssertEqual(counting.reads(of: remove), 1)
        }
    }

    /// The half the cache must not weaken: the copy going to the Trash is read
    /// from disk on every call, even when the same path is asked about twice.
    func testTheVictimIsReadFromDiskOnEveryCall() throws {
        let keep = try write("keep.bin", "the same bytes")
        let remove = try write("copy.bin", "the same bytes")
        let counting = CountingHash()
        let batch = DuplicateVerification.Batch(hash: counting.hash)

        XCTAssertEqual(batch.verify(remove: remove, keep: keep), .identical)
        XCTAssertEqual(batch.verify(remove: remove, keep: keep), .identical)

        XCTAssertEqual(counting.reads(of: remove), 2,
                       "the victim's read was cached, which is the read the guarantee is about")
    }

    /// Two groups are two survivors, each read once — the memo is per keep
    /// path, not one slot.
    func testTwoGroupsReadTwoSurvivors() throws {
        let keepA = try write("keepA.bin", "family a")
        let keepB = try write("keepB.bin", "family b")
        let removeA = try write("copyA.bin", "family a")
        let removeB = try write("copyB.bin", "family b")
        let counting = CountingHash()
        let batch = DuplicateVerification.Batch(hash: counting.hash)

        XCTAssertEqual(batch.verify(remove: removeA, keep: keepA), .identical)
        XCTAssertEqual(batch.verify(remove: removeB, keep: keepB), .identical)
        XCTAssertEqual(batch.verify(remove: removeA, keep: keepA), .identical)

        XCTAssertEqual(counting.reads(of: keepA), 1)
        XCTAssertEqual(counting.reads(of: keepB), 1)
    }

    /// A survivor that cannot be read refuses every pair that names it — and a
    /// verdict from the memo is the same verdict a fresh read gave.
    func testAnUnreadableSurvivorRefusesEveryPairThatNamesIt() throws {
        let remove = try write("copy.bin", "content")
        let gone = directory.appendingPathComponent("gone.bin").path
        let batch = DuplicateVerification.Batch()

        XCTAssertEqual(batch.verify(remove: remove, keep: gone), .unreadable)
        XCTAssertEqual(batch.verify(remove: remove, keep: gone), .unreadable)
    }

    /// An edited copy is caught against the memoised survivor: the cache must
    /// not turn "changed" into "identical".
    func testAnEditedCopyIsStillCaughtAgainstTheMemo() throws {
        let keep = try write("keep.bin", "the same bytes")
        let good = try write("good.bin", "the same bytes")
        let edited = try write("edited.bin", "not the same!!")
        let sameSize = try write("samesize.bin", "the same bytez")
        let batch = DuplicateVerification.Batch()

        XCTAssertEqual(batch.verify(remove: good, keep: keep), .identical)
        XCTAssertEqual(batch.verify(remove: edited, keep: keep), .changed)
        XCTAssertEqual(batch.verify(remove: sameSize, keep: keep), .changed)
    }

    /// A hard link of the survivor is one file wearing two names, and the memo
    /// carries the survivor's inode so the second pair is refused too.
    func testAHardLinkOfTheSurvivorIsRefusedThroughTheMemo() throws {
        let keep = try write("keep.bin", "shared content")
        let extra = try write("extra.bin", "shared content")
        let link = directory.appendingPathComponent("link.bin").path
        try FileManager.default.linkItem(atPath: keep, toPath: link)
        let batch = DuplicateVerification.Batch()

        XCTAssertEqual(batch.verify(remove: extra, keep: keep), .identical)
        XCTAssertEqual(batch.verify(remove: link, keep: keep), .changed)
    }
}
