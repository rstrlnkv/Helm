import Foundation
import HelmRuntime
import XCTest
@testable import Module_Disk_Engine

/// What one walk costs the process, and which of its two loops the cost is in.
///
/// ARCHITECTURE.md § Memory reaches both. The **worker** loop asks Foundation
/// for a directory at a time and has had its pool for as long as that section
/// has existed. The **builder** loop — `while let batch = channel.pop()`, on the
/// calling thread — had none, and it is where every path string in the scan is
/// made: `TreeBuilder.insert` bridges through `NSString` twice per file, and
/// `charge` does it once more per ancestor level on the way up. Nothing drains
/// those: the loop runs inside `offTheCooperativePool`, so the pool they belong
/// to is the one that closes when the whole scan is over.
///
/// **Against a tree this file builds, not against the owner's home directory,
/// and not behind an environment variable.** This test used to be both, and so
/// could not fail on the thing it names: it was skipped unless `HELM_BENCH=1`,
/// and its ceiling of 2000 bytes a file sat above the defect it was guarding.
/// The reading that answers this question is a difference between two runs of
/// the same code over the same tree; a home directory is neither the same
/// between two machines nor the same between two afternoons, and a threshold
/// loose enough to survive both is a threshold loose enough to survive the bug.
///
/// The fixture is narrow and deep on purpose. The cost is per *path component
/// composed*, not per file, so depth is the axis that makes a few thousand
/// files say what a hundred thousand shallow ones would not.
final class ScanFootprintTests: XCTestCase {

    /// Deep enough that `charge` walks a real path, small enough that the whole
    /// case — fixture, warm-up walk and measured walk — costs about six seconds.
    /// Both numbers are stated here because the threshold below is a fact about
    /// *this* fixture and means nothing away from it.
    private static let depth = 16
    private static let files = 8_000

    private final class ProgressBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = 0
        func record(_ n: Int) { lock.lock(); stored = n; lock.unlock() }
        var filesSeen: Int { lock.lock(); defer { lock.unlock() }; return stored }
    }

    /// `depth` nested directories with `files` empty files at the bottom.
    ///
    /// Empty on purpose: a file under the fold threshold takes the branch that
    /// makes no node at all, so what is left to measure is the path arithmetic
    /// and nothing else — a tree of nodes would put the thing this is separating
    /// the defect from back into the reading.
    private func deepTree(in root: URL) throws {
        var deepest = root
        for level in 0..<Self.depth {
            deepest = deepest.appendingPathComponent("level\(level)")
        }
        try FileManager.default.createDirectory(at: deepest, withIntermediateDirectories: true)
        for index in 0..<Self.files {
            FileManager.default.createFile(atPath: deepest.appendingPathComponent("f\(index)").path,
                                           contents: nil)
        }
    }

    func testTheBuilderLoopCostsItsTreeAndNotEveryPathItComposed() throws {
        let root = scratchDirectory("disk-footprint")
        try deepTree(in: root)

        // The allocator keeps its tools out — ARCHITECTURE.md § Memory measured
        // the peak falling with every round and settling by the third — so the
        // first walk pays for whatever Foundation warms up once, and the reading
        // that answers the question is the second.
        _ = DiskScanner().scan(root: root.path)

        let box = ProgressBox()
        let before = try XCTUnwrap(MemoryFootprint.current())
        let tree = DiskScanner().scan(root: root.path,
                                      onProgress: { box.record($0.filesSeen) })
        let after = try XCTUnwrap(MemoryFootprint.current())

        XCTAssertNotNil(tree, "the fixture did not walk at all")
        let seen = box.filesSeen
        // Asserted, not assumed: a walk that found nothing divides a footprint
        // difference by a small number and passes whatever the loop did.
        XCTAssertGreaterThanOrEqual(seen, Self.files,
                                    "the walk found \(seen) of \(Self.files) files, so this is "
                                    + "measuring something smaller than it was written for")

        let perFile = Double(after - before) / Double(seen)
        print(String(format: "walked %d files at depth %d: footprint grew %.1f MB (%.0f bytes/file)",
                     seen, Self.depth, Double(after - before) / 1_048_576, perFile))

        // **The threshold sits between two measurements of this fixture**, taken
        // three times each on the machine this was written on:
        //
        //     builder loop with no pool:   4,0 MB grown, 528 bytes/file
        //     the same loop inside one:    0,0 MB grown, 4–10 bytes/file
        //
        // 150 fails on the defect by a factor of three and a half and passes the
        // repair by fifteen. A number above both readings would have recorded
        // the present rather than guarded it.
        XCTAssertLessThan(perFile, 150, """
            the walk is keeping every path it composed rather than the tree it built. \
            `TreeBuilder` bridges through NSString twice per file and once per ancestor \
            level, and nothing drains those until the whole scan returns — check the \
            autoreleasepool inside `while let batch = channel.pop()` in DiskScanner.scan.
            """)
    }
}
