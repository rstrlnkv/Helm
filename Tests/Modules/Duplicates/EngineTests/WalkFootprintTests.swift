import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// What the *walk* costs, as opposed to the hashing.
///
/// **This one is the answer to a suspicion, and the answer was no.**
/// `HashingFootprintTests` beside it guards the read loop, and `DiskScanner`'s
/// walk carries an `autoreleasepool` under a comment calling the duplicate
/// finder's read loop «the same defect, one framework call further out»
/// (ARCHITECTURE.md § Memory: «at 1.5 M entries that was most of what looked
/// like the cost of the tree»). This walk has no pool, asks Foundation for five
/// resource values per entry, `lstat`s twice and calls `getattrlist` for every
/// candidate — so it reads exactly like the next place to find that defect.
///
/// Measured instead of assumed, over this machine's real home directory:
///
///     walked 365 615 entries in 16,14 s, kept 12 667 files:
///     footprint grew 8,5 MB (24 bytes/entry)
///
/// 8,5 MB across 12 667 kept `FileFacts` is about 670 bytes for each file the
/// walk keeps, and the entries it merely looked at cost nothing that survives
/// the loop. A pool here would have been added on the strength of the story
/// rather than of a reading. What the bound below pins is that this stays true:
/// the cost must follow the files kept, never the tree walked.
///
/// Over the real home directory, like `ScanFootprintTests` does: a synthetic
/// tree big enough to show this costs more to build than the walk being
/// measured. Read-only — the walk opens nothing and writes nothing.
///
///     HELM_BENCH=1 swift test --filter WalkFootprintTests
final class WalkFootprintTests: XCTestCase {

    func testTheWalkCostsItsTreeAndNotEverythingItLookedAt() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HELM_BENCH"] == "1")
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let scanner = DuplicateScanner()
        let box = ProgressBox()
        let before = try XCTUnwrap(MemoryFootprint.current())
        let started = Date()
        // The walk alone: `find` would hash whatever it nominates, and the
        // hashing is the other test's subject.
        let files = scanner.walk(home, onProgress: { progress in box.record(progress.hashed) })
        let after = try XCTUnwrap(MemoryFootprint.current())

        let grew = after - before
        let seen = box.value
        let perEntry = seen > 0 ? Double(grew) / Double(seen) : 0
        print(String(format: "walked %d entries in %.2f s, kept %d files: "
                     + "footprint grew %.1f MB (%.0f bytes/entry)",
                     seen, Date().timeIntervalSince(started), files.count,
                     Double(grew) / 1_048_576, perEntry))

        try XCTSkipIf(seen < 10_000, "only \(seen) entries here; nothing to measure")
        // 24 bytes/entry measured. The bound is an order of magnitude above it
        // — a real home varies machine to machine — and two orders below what
        // a walk that kept what it read would show: every entry carries a URL,
        // a `URLResourceValues` and two `stat` buffers through the loop, which
        // is hundreds of bytes apiece over 365k entries.
        XCTAssertLessThan(perEntry, 200,
                          "the walk is scaling with what it looked at rather than with the "
                          + "files it kept — an autoreleasepool inside the enumerator loop "
                          + "is what fixed the same shape in DiskScanner")
    }
}
