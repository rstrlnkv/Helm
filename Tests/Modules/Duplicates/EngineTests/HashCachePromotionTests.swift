import XCTest
@testable import Module_Duplicates_Engine

/// The segment design's own claim is absolute: "Nothing is evicted, because
/// nothing that is still on the disk is ever absent from `fresh`." These probe
/// the one code path that can make that untrue — `promote`, which is the only
/// place `fresh` is written by something other than a `set…` call.
final class HashCachePromotionTests: XCTestCase {

    private let now: TimeInterval = 1_800_000_000

    /// **Promotion replaces the fresh entry; it does not merge with it.**
    ///
    /// ```swift
    /// if let entry = fresh[key], let digest = read(entry) { return digest }
    /// guard let entry = settled[key], let digest = read(entry) else { return nil }
    /// fresh[key] = entry          // ← the whole entry, over the whole entry
    /// ```
    ///
    /// The existing `testPromotionCarriesBothDigests` pins the direction where
    /// `settled` is the richer half. This is the other direction: `fresh`
    /// already holds a digest this scan computed, `settled` holds the *other*
    /// half, and reading the settled half throws the computed one away.
    ///
    /// A cache with no eviction policy forgetting something it was explicitly
    /// told is worse than a slow scan — after the next compaction the loss is
    /// permanent, and the file it belonged to is read in full again.
    func testPromotionDoesNotDiscardWhatTheFreshSegmentAlreadyHeld() {
        var cache = HashCache(now: now)
        cache.setPrefix("p", fileID: 1, bytes: 10, modified: 5)
        cache = cache.compacted(now: now)                      // settled: prefix only
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)  // fresh: full only

        XCTAssertEqual(cache.prefix(fileID: 1, bytes: 10, modified: 5), "p",
                       "fixture: the settled prefix is the read that promotes")
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f",
                       "the digest this scan computed was overwritten by the promotion")
    }

    /// The same loss, one compaction later, which is where it stops being
    /// recoverable: the entry `settled` holds after `settled := fresh` is the
    /// half that survived the overwrite.
    func testTheDiscardedDigestIsNotRecoveredByCompaction() {
        var cache = HashCache(now: now)
        cache.setPrefix("p", fileID: 1, bytes: 10, modified: 5)
        cache = cache.compacted(now: now)
        cache.setFull("f", fileID: 1, bytes: 10, modified: 5)
        _ = cache.prefix(fileID: 1, bytes: 10, modified: 5)
        cache = cache.compacted(now: now)
        XCTAssertEqual(cache.full(fileID: 1, bytes: 10, modified: 5), "f")
    }

    /// A digest that was written and never read back is still a digest the
    /// cache was told. This is the same defect stated without the compaction
    /// vocabulary: two writes and two reads, and one of the four answers is
    /// gone.
    func testEveryDigestWrittenIsStillReadable() {
        var cache = HashCache(now: now)
        cache.setFull("f", fileID: 9, bytes: 90, modified: 9)
        cache = cache.compacted(now: now)                       // settled: full only
        cache.setPrefix("p", fileID: 9, bytes: 90, modified: 9) // fresh: prefix only
        XCTAssertEqual(cache.prefix(fileID: 9, bytes: 90, modified: 9), "p")
        XCTAssertEqual(cache.full(fileID: 9, bytes: 90, modified: 9), "f")
        XCTAssertEqual(cache.prefix(fileID: 9, bytes: 90, modified: 9), "p",
                       "reading the settled half discarded the fresh one")
    }
}
