import XCTest
@testable import Module_Duplicates_Engine

final class HashCacheTests: XCTestCase {

    private let now: TimeInterval = 1_800_000_000

    func testADigestComesBackForTheSameFile() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: 1_785_600_000)
        XCTAssertEqual(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_000), "abc")
    }

    /// The three facts that make up identity, one at a time. Any of them
    /// changing means the digest on file describes a different state of the
    /// world, and reusing it is the mistake this key exists to prevent.
    func testAnyChangeInIdentityMissesTheCache() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: 1_785_600_000)
        XCTAssertNil(cache.full(fileID: 43, bytes: 100, modified: 1_785_600_000), "inode")
        XCTAssertNil(cache.full(fileID: 42, bytes: 101, modified: 1_785_600_000), "size")
        XCTAssertNil(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_001), "mtime")
    }

    /// A file with no readable modification time must still be a stable key, or
    /// nothing about it is ever cached.
    func testAMissingModificationTimeIsItsOwnKey() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: nil)
        XCTAssertEqual(cache.full(fileID: 42, bytes: 100, modified: nil), "abc")
        XCTAssertNil(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_000))
    }

    /// APFS records nanoseconds, and rounding to whole seconds would let a file
    /// edited twice within one second reuse the digest of its earlier state.
    func testSubSecondChangesAreDistinct() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: 1_785_600_000.100000)
        XCTAssertNil(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_000.200000))
    }

    /// The search takes the prefix of everything and the full hash of only what
    /// survives that pass, so the two are separate slots for one file.
    func testPrefixAndFullAreIndependent() {
        let cache = HashCache()
        cache.setPrefix("p", fileID: 1, bytes: 10, modified: 5)
        XCTAssertEqual(cache.prefix(fileID: 1, bytes: 10, modified: 5), "p")
        XCTAssertNil(cache.full(fileID: 1, bytes: 10, modified: 5))
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)
        XCTAssertEqual(cache.prefix(fileID: 1, bytes: 10, modified: 5), "p")
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f")
    }

    // MARK: - The two segments

    /// **The test the whole design turns on.** A file that never changes is only
    /// ever *read* from the settled segment. If a hit does not copy it into the
    /// fresh one, compaction — which is `settled := fresh` — forgets exactly the
    /// files a cache is most valuable for.
    func testAHitInTheSettledSegmentSurvivesCompaction() {
        var cache = HashCache(now: now)
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)
        cache = cache.compacted(now: now)          // now it lives in `settled`
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f", "still readable")
        cache = cache.compacted(now: now)          // the read must have promoted it
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f",
                       "a file that never changed was forgotten")
    }

    /// A file nobody looked at through a whole cycle is gone, which is what
    /// bounds the map by the disk rather than by history.
    func testAnUntouchedEntryIsDroppedByCompaction() {
        var cache = HashCache(now: now)
        cache.setFull("gone", fileID: 1, bytes: 10, modified: 5)
        cache.setFull("kept", fileID: 2, bytes: 20, modified: 6)
        cache = cache.compacted(now: now)
        _ = cache.full(fileID: 2, bytes: 20, modified: 6)   // only this one is seen
        cache = cache.compacted(now: now)
        XCTAssertEqual(cache.full(fileID: 2, bytes: 20, modified: 6), "kept")
        XCTAssertNil(cache.full(fileID: 1, bytes: 10, modified: 5))
    }

    /// Promotion carries the whole entry. The prefix and the full digest are
    /// read in two separate passes, so promoting only the half that was asked
    /// for would leave the other in a segment about to be replaced.
    func testPromotionCarriesBothDigests() {
        var cache = HashCache(now: now)
        cache.setPrefix("p", fileID: 1, bytes: 10, modified: 5)
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)
        cache = cache.compacted(now: now)
        _ = cache.prefix(fileID: 1, bytes: 10, modified: 5)  // only the prefix is asked for
        cache = cache.compacted(now: now)
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f",
                       "the full digest was left behind")
    }

    /// Deferring compaction is what makes a file that left and came back cheap:
    /// its digest waits in the settled segment for up to a month.
    func testCompactionWaitsUntilTheSegmentIsStale() {
        let cache = HashCache(now: now)
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)
        XCTAssertTrue(cache.compactedIfStale(now: now + HashCache.maximumAge) === cache,
                      "compacted early")
        XCTAssertFalse(cache.compactedIfStale(now: now + HashCache.maximumAge + 1) === cache,
                       "did not compact when stale")
    }

    func testItSurvivesARoundTrip() throws {
        var cache = HashCache(now: now)
        cache.setPrefix("p", fileID: 7, bytes: 70, modified: 7)
        cache = cache.compacted(now: now)
        cache.setFull("f", fileID: 8, bytes: 80, modified: 8)
        let back = try JSONDecoder().decode(HashCache.self,
                                            from: try JSONEncoder().encode(cache))
        XCTAssertEqual(back.prefix(fileID: 7, bytes: 70, modified: 7), "p", "settled segment")
        XCTAssertEqual(back.full(fileID: 8, bytes: 80, modified: 8), "f", "fresh segment")
    }

    /// The search hashes under `concurrentPerform`, so every reader and writer
    /// arrives from a different thread at once. A bare dictionary under that is
    /// undefined behaviour rather than a wrong answer.
    func testConcurrentWritesDoNotLoseEntries() {
        let cache = HashCache()
        DispatchQueue.concurrentPerform(iterations: 500) { i in
            cache.setFull("d\(i)", fileID: UInt64(i), bytes: i, modified: TimeInterval(i))
            _ = cache.full(fileID: UInt64(i), bytes: i, modified: TimeInterval(i))
        }
        XCTAssertEqual(cache.count, 500)
    }

    /// Promotion happens under the same lock, so a scan reading the settled
    /// segment from every core at once must not lose or duplicate entries.
    func testConcurrentPromotionIsSafe() {
        var cache = HashCache(now: now)
        for i in 0..<500 { cache.setFull("d\(i)", fileID: UInt64(i), bytes: i, modified: 1) }
        cache = cache.compacted(now: now)
        let settled = cache
        DispatchQueue.concurrentPerform(iterations: 500) { i in
            _ = settled.full(fileID: UInt64(i), bytes: i, modified: 1)
        }
        XCTAssertEqual(settled.count, 500)
    }
}
