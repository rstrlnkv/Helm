import XCTest
@testable import Module_Duplicates_Engine

final class HashCacheTests: XCTestCase {

    func testADigestComesBackForTheSameFile() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: 1_785_600_000)
        XCTAssertEqual(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_000), "abc")
    }

    /// The three facts that make up identity, one at a time. Any of them
    /// changing means the digest on file describes a different state of the
    /// world, and reusing it is exactly the mistake this key exists to prevent.
    func testAnyChangeInIdentityMissesTheCache() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: 1_785_600_000)
        XCTAssertNil(cache.full(fileID: 43, bytes: 100, modified: 1_785_600_000), "inode")
        XCTAssertNil(cache.full(fileID: 42, bytes: 101, modified: 1_785_600_000), "size")
        XCTAssertNil(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_001), "mtime")
    }

    /// A file with no readable modification time must not collide with every
    /// other such file of the same size — but it must still be a stable key, or
    /// nothing about it is ever cached.
    func testAMissingModificationTimeIsItsOwnKey() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: nil)
        XCTAssertEqual(cache.full(fileID: 42, bytes: 100, modified: nil), "abc")
        XCTAssertNil(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_000))
    }

    /// Sub-second resolution is kept. APFS records nanoseconds, and rounding to
    /// whole seconds would let a file edited twice within one second reuse the
    /// digest of its earlier state.
    func testSubSecondChangesAreDistinct() {
        let cache = HashCache()
        cache.setFull("abc", fileID: 42, bytes: 100, modified: 1_785_600_000.100000)
        XCTAssertNil(cache.full(fileID: 42, bytes: 100, modified: 1_785_600_000.200000))
    }

    /// The prefix and the full digest are separate slots for one file: the
    /// search takes the prefix of everything and the full hash of only what
    /// survives that pass.
    func testPrefixAndFullAreIndependent() {
        let cache = HashCache()
        cache.setPrefix("p", fileID: 1, bytes: 10, modified: 5)
        XCTAssertEqual(cache.prefix(fileID: 1, bytes: 10, modified: 5), "p")
        XCTAssertNil(cache.full(fileID: 1, bytes: 10, modified: 5))
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)
        XCTAssertEqual(cache.prefix(fileID: 1, bytes: 10, modified: 5), "p")
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f")
    }

    /// Without an expiry the file grows forever: an edited file takes a *new*
    /// key rather than replacing its old one, so every state of every file ever
    /// hashed would stay.
    func testEntriesOlderThanThirtyDaysAreDropped() {
        let now: TimeInterval = 1_800_000_000
        let cache = HashCache()
        cache.setFull("old", fileID: 1, bytes: 10, modified: 1,
                      now: now - HashCache.maximumAge - 1)
        cache.setFull("fresh", fileID: 2, bytes: 20, modified: 2, now: now)
        let pruned = cache.pruned(now: now)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.full(fileID: 2, bytes: 20, modified: 2, now: now), "fresh")
    }

    /// Exactly thirty days is kept. `>` against `>=` is one character and a
    /// scan's worth of re-reading.
    func testExactlyTheLimitIsKept() {
        let now: TimeInterval = 1_800_000_000
        let cache = HashCache()
        cache.setFull("d", fileID: 1, bytes: 10, modified: 1, now: now - HashCache.maximumAge)
        XCTAssertEqual(cache.pruned(now: now).count, 1)
    }

    /// **A read has to postpone the expiry**, or a file that never changes ages
    /// out and is re-read every thirty days — which is the one case the cache
    /// exists for. This is the test that fails if the stamp is only written on
    /// a miss.
    func testReadingAnEntryKeepsItAlive() {
        let now: TimeInterval = 1_800_000_000
        let cache = HashCache()
        cache.setFull("d", fileID: 1, bytes: 10, modified: 1,
                      now: now - HashCache.maximumAge + 10)
        // Read it just before it would have expired.
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 1, now: now), "d")
        // A month later it is still there, because the read moved it forward.
        XCTAssertEqual(cache.pruned(now: now + HashCache.maximumAge).count, 1)
    }

    /// A miss must not create an entry. Otherwise every file the scan reads for
    /// the first time is counted twice against the limit — once empty from the
    /// lookup, once real from the write.
    func testAMissLeavesNothingBehind() {
        let cache = HashCache()
        XCTAssertNil(cache.full(fileID: 99, bytes: 10, modified: 1))
        XCTAssertEqual(cache.count, 0)
    }

    /// The age limit is a rate, not a ceiling: a disk that churns faster than
    /// thirty days grows without bound inside them. The count is the backstop,
    /// and it keeps the most recently used.
    func testTheCountIsTheBackstopAndKeepsTheNewest() {
        let now: TimeInterval = 1_800_000_000
        let cache = HashCache()
        for i in 0..<50 {
            cache.setFull("d\(i)", fileID: UInt64(i), bytes: 10, modified: 1,
                          now: now - TimeInterval(50 - i))
        }
        let pruned = cache.pruned(now: now, limit: 10)
        XCTAssertEqual(pruned.count, 10)
        // The newest ten are 40…49; the oldest are gone.
        XCTAssertNotNil(pruned.full(fileID: 49, bytes: 10, modified: 1, now: now))
        XCTAssertNil(pruned.full(fileID: 0, bytes: 10, modified: 1, now: now))
    }

    func testItSurvivesARoundTrip() throws {
        let cache = HashCache()
        cache.setPrefix("p", fileID: 7, bytes: 70, modified: 7)
        cache.setFull("f", fileID: 7, bytes: 70, modified: 7)
        let data = try JSONEncoder().encode(cache)
        let back = try JSONDecoder().decode(HashCache.self, from: data)
        XCTAssertEqual(back.prefix(fileID: 7, bytes: 70, modified: 7), "p")
        XCTAssertEqual(back.full(fileID: 7, bytes: 70, modified: 7), "f")
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
}
