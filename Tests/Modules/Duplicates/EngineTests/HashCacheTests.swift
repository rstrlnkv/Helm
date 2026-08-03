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

    /// Without pruning the file grows forever: an edited file takes a *new* key
    /// rather than replacing its old one, so every version of every file ever
    /// hashed would stay.
    func testPruningKeepsOnlyWhatTheScanTouched() {
        let cache = HashCache()
        cache.setFull("a", fileID: 1, bytes: 10, modified: 1)
        cache.setFull("b", fileID: 2, bytes: 20, modified: 2)
        let live: Set<String> = [HashCache.key(fileID: 2, bytes: 20, modified: 2)]
        let pruned = cache.keeping(live)
        XCTAssertEqual(pruned.count, 1)
        XCTAssertEqual(pruned.full(fileID: 2, bytes: 20, modified: 2), "b")
        XCTAssertNil(pruned.full(fileID: 1, bytes: 10, modified: 1))
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
