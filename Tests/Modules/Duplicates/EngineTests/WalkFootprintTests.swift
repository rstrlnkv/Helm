import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// What the *walk* costs, as opposed to the hashing — and the rule it pins:
/// the cost follows the files kept, never the tree walked.
///
/// **Against a tree this file builds, not against the owner's home directory,
/// and not behind an environment variable.** This test used to be both — skipped
/// unless `HELM_BENCH=1`, walking a real home — and so could not fail on the
/// thing it names: a guard behind a flag catches nothing, and a threshold loose
/// enough to survive two different Macs is loose enough to survive the bug.
/// Disk's `ScanFootprintTests` made the same move first and says why the
/// reading has to be a difference between two runs of the same code over the
/// same tree.
///
/// The original home-directory measurement stays on record, because it is what
/// answered the suspicion this file began as: 365 615 entries, 12 667 kept,
/// 8,5 MB grown — 24 bytes an entry, so the walk with no `autoreleasepool` was
/// *not* the DiskScanner defect one framework call further out, and a pool here
/// would have been added on the strength of the story rather than of a reading.
/// That measurement was taken of a `FileManager` enumeration; the loop under
/// this test is `BulkWalk.walk` now, which carries the pools the rule asks for,
/// and the threshold below is what says the promotion did not put the cost back.
final class WalkFootprintTests: XCTestCase {

    /// Small files below the size floor, so the walk looks at every one and
    /// keeps none — what is measured is the looking. Spread over directories
    /// because a real tree is not a single folder of ten thousand names, and
    /// the enumerator's per-directory work is part of the loop being measured.
    private static let directories = 16
    private static let filesPerDirectory = 500
    private static var looked: Int { directories * filesPerDirectory + directories + kept }
    /// Above the floor and identical, so the walk's answer is not empty and the
    /// subject assertion below has something to hold.
    private static let kept = 2

    private func tree(in root: URL) throws {
        for directory in 0..<Self.directories {
            for index in 0..<Self.filesPerDirectory {
                try write("d\(directory)/f\(index).bin", in: root, bytes: 4)
            }
        }
        try write("kept-a.bin", in: root, bytes: 1_200_000, filler: 9)
        try write("kept-b.bin", in: root, bytes: 1_200_000, filler: 9)
    }

    func testTheWalkCostsItsTreeAndNotEverythingItLookedAt() throws {
        let root = scratchDirectory("dup-walk-footprint")
        try tree(in: root)

        // The first walk pays for whatever Foundation warms up once — the
        // allocator keeps its tools out — so the reading that answers the
        // question is the second. The same order as `ScanFootprintTests`.
        _ = DuplicateScanner().walk(root.path, onProgress: nil)

        // The allocator's books, not `phys_footprint`: a walk of this size
        // retaining every entry grows `size_in_use` by 190 bytes an entry and
        // grows the footprint by nothing at all — the reading was taken, and it
        // is the same instrument failure CLAUDE.md records for a cache fill.
        let before = AllocatorBooks.allocatedBytes()
        let files = DuplicateScanner().walk(root.path, onProgress: nil)
        let after = AllocatorBooks.allocatedBytes()

        // The subject first: the walk really read the fixture. The denominator
        // below is the fixture's own count, because the progress channel is
        // throttled to a tick every 0.35 s and a walk this size finishes inside
        // one — a denominator read from it would divide by nearly nothing.
        XCTAssertEqual(files.count, Self.kept,
                       "the walk kept \(files.count) of \(Self.kept) fixture files, so this "
                       + "is measuring something other than it was written for")

        let perEntry = Double(after - before) / Double(Self.looked)
        print(String(format: "walked %d entries, kept %d: footprint grew %.1f MB "
                     + "(%.0f bytes/entry)",
                     Self.looked, files.count, Double(after - before) / 1_048_576, perEntry))

        // **The threshold sits between two measurements of this fixture**, taken
        // three times each on the machine this was written on:
        //
        //     the walk as it is:                  0,0 MB grown, 3 bytes/entry
        //     keeping what it only looked at:     2,0 MB grown, 261 bytes/entry
        //
        // 100 fails on the defect by a factor of two and a half and passes the
        // healthy walk by thirty. The defect planted for the readings was the
        // size floor deleted — every entry's `FileFacts` retained — which is the
        // smallest way the walk can start scaling with the tree instead of with
        // its answer.
        XCTAssertLessThan(perEntry, 100, """
            the walk is scaling with what it looked at rather than with the files it \
            kept — every entry is carrying something out of the loop. The loop is \
            `BulkWalk.walk`'s now, and it has a pool per directory and a pool per batch; \
            check that both are still there before looking at this file's own filter.
            """)
    }
}
