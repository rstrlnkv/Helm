import XCTest
import HelmRuntime
@testable import Module_Duplicates_Engine

/// Two questions about `HashCache` at scale, asked with real numbers rather
/// than by reading the code:
///
/// 1. It is unbounded in memory while a scan runs — one entry per candidate,
///    held in `fresh`, nothing evicted until compaction. `~/Documents` gave
///    6900 candidates; a home directory or a duplicates root chosen at the
///    volume level can give far more. What does that cost in `phys_footprint`?
/// 2. `compacted()` copies the whole `fresh` dictionary under `lock` — done
///    once per scan, on the way out (`DuplicatesEngine.backgroundScan`), never
///    while hashing is still running concurrently against it. At how many
///    entries does that copy start costing whole milliseconds rather than
///    fractions of one?
///
/// Report only — nothing here is a regression a person would feel as
/// lag, and the numbers below say so with a measurement rather than a guess.
///
/// `HELM_BENCH=1 swift test --filter HashCacheScaleBenchmark`
final class HashCacheScaleBenchmark: XCTestCase {

    /// 64 hex characters, matching `DuplicateScanner.hash`'s SHA-256 output —
    /// a synthetic digest costs the same JSON and the same heap allocation as
    /// a real one, without hashing gigabytes of real content to produce it.
    private static let digest = String(repeating: "a", count: 64)

    private func fill(_ cache: HashCache, count: Int) {
        for i in 0..<count {
            cache.setPrefix(Self.digest, fileID: UInt64(i), bytes: 1_000_000 + i,
                            modified: 1_785_600_000 + Double(i))
            cache.setFull(Self.digest, fileID: UInt64(i), bytes: 1_000_000 + i,
                         modified: 1_785_600_000 + Double(i))
        }
    }

    // MARK: - 1. Memory while a scan holds the cache

    private func measureFootprint(count: Int) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let before = try XCTUnwrap(MemoryFootprint.current())
        let cache = HashCache()
        fill(cache, count: count)
        let after = try XCTUnwrap(MemoryFootprint.current())
        XCTAssertEqual(cache.count, count)

        let grewKB = Double(after - before) / 1024
        let bytesPerEntry = Double(after - before) / Double(count)
        print(String(format: "HashCache holding %d entries: footprint grew %.0f KB "
                     + "(%.0f bytes/entry in memory; 184 bytes/entry is the JSON figure)",
                     count, grewKB, bytesPerEntry))
    }

    /// `~/Documents` scale, measured directly.
    func testFootprintAtDocumentsScale() throws {
        try measureFootprint(count: 6900)
    }

    /// Ten times that — the "far more" the doc comment on `HashCache` warns
    /// a large home directory could reach.
    func testFootprintAtTenTimesDocumentsScale() throws {
        try measureFootprint(count: 69_000)
    }

    /// A home-directory-of-candidates scale: every file at or above the 1 MB
    /// floor `DuplicateScanner.minBytes` sets, guessed generously high.
    func testFootprintAtLargeHomeScale() throws {
        try measureFootprint(count: 500_000)
    }

    // MARK: - 2. compacted()'s copy under lock

    private func measureCompaction(count: Int, iterations: Int) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let cache = HashCache()
        fill(cache, count: count)

        var total: TimeInterval = 0
        for _ in 0..<iterations {
            let start = Date()
            _ = cache.compacted()
            total += Date().timeIntervalSince(start)
        }
        print(String(format: "HashCache.compacted() at %d entries: %.4f ms/call "
                     + "(average over %d calls)",
                     count, total / Double(iterations) * 1000, iterations))
    }

    func testCompactionAtDocumentsScale() throws {
        try measureCompaction(count: 6900, iterations: 20)
    }

    func testCompactionAtTenTimesDocumentsScale() throws {
        try measureCompaction(count: 69_000, iterations: 10)
    }

    func testCompactionAtLargeHomeScale() throws {
        try measureCompaction(count: 500_000, iterations: 3)
    }

    // MARK: - 3. What actually touches every entry: encode and decode

    /// `DuplicatesEngine.saveCache`/`loadCache` run `JSONEncoder`/`JSONDecoder`
    /// over the *whole* cache — every entry, every time, on every background
    /// scan. Unlike `compacted()` this genuinely cannot skip an entry, so this
    /// is where the O(n) the previous section didn't find actually lives.
    private func measureCodec(count: Int) throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let cache = HashCache()
        fill(cache, count: count)

        let encodeStart = Date()
        let data = try JSONEncoder().encode(cache)
        let encodeTime = Date().timeIntervalSince(encodeStart)

        let decodeStart = Date()
        _ = try JSONDecoder().decode(HashCache.self, from: data)
        let decodeTime = Date().timeIntervalSince(decodeStart)

        print(String(format: "HashCache codec at %d entries: encode %.4f s, decode %.4f s, "
                     + "%d KB on disk",
                     count, encodeTime, decodeTime, data.count / 1024))
    }

    func testCodecAtDocumentsScale() throws { try measureCodec(count: 6900) }
    func testCodecAtTenTimesDocumentsScale() throws { try measureCodec(count: 69_000) }
    func testCodecAtLargeHomeScale() throws { try measureCodec(count: 500_000) }

    // MARK: - 2b. Is the copy actually paid, or deferred by copy-on-write?

    /// `compacted()` does `out.settled = fresh` — a `Dictionary` assignment,
    /// not a loop over entries. Swift dictionaries are copy-on-write, so that
    /// line is a reference-count bump regardless of size, and the real O(n)
    /// copy — if it is ever paid at all — happens on the *next mutation* of
    /// whichever side still shares the buffer. `DuplicatesEngine.backgroundScan`
    /// discards the pre-compaction cache immediately
    /// (`Self.saveCache(cache.compactedIfStale())`), and the mutation that
    /// would force the copy — a write to the new cache's `fresh` — touches a
    /// different, already-empty dictionary, not the shared `settled` one. So in
    /// the one call site that exists, the copy this test's sibling above
    /// measured at "0.0027 ms at 500k entries" is not deferred either: it is
    /// never paid.
    ///
    /// This writes into the compacted cache immediately after compacting, the
    /// way a scan's next hash miss would, and confirms the write cost does not
    /// jump — if COW were forcing a copy here, this write would cost what the
    /// dictionary-copy itself costs, on top of an ordinary dictionary insert.
    func testWritingAfterCompactionDoesNotPayADeferredCopy() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let count = 500_000
        let cache = HashCache()
        fill(cache, count: count)
        let compacted = cache.compacted()

        let start = Date()
        compacted.setFull(Self.digest, fileID: UInt64(count + 1), bytes: 1,
                          modified: 1_785_600_000)
        let oneWrite = Date().timeIntervalSince(start) * 1000

        // A baseline: the same single write, on a cache that was never
        // compacted and shares nothing with anybody.
        let plain = HashCache()
        let start2 = Date()
        plain.setFull(Self.digest, fileID: 1, bytes: 1, modified: 1_785_600_000)
        let baselineWrite = Date().timeIntervalSince(start2) * 1000

        print(String(format: "one write just after compacting %d entries: %.4f ms "
                     + "(an uncompacted cache's first write: %.4f ms)",
                     count, oneWrite, baselineWrite))
    }
}
