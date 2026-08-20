import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// What the sweep at the end of a scan costs the process.
///
/// ARCHITECTURE.md § Memory: **any loop that reads file contents or asks
/// Foundation for resource values in bulk needs a pool inside it.**
/// `DiskAdvisor.sweep` is such a loop and had no pool. It visits every file node
/// in the finished tree and asks `UserFileScope.isRemovable` about each one —
/// which is `NSString.standardizingPath`, a `FileManager.fileExists` walk up the
/// parent chain and `URL.resolvingSymlinksInPath`, all of it Foundation handing
/// back autoreleased objects. The sweep runs inside `offTheCooperativePool` on
/// the scan's own thread, so the pool those objects belong to is the one that
/// closes when the **whole scan** returns: everything the advisor ever looked at
/// stays alive until then, on top of the tree it is looking at.
///
/// Measured against the allocator's books rather than `MemoryFootprint.current()`
/// — CLAUDE.md § A per-object memory cost: `phys_footprint` answers what the
/// process costs the machine and has read 0 KB over a fill that really did
/// allocate.
final class TheAdvisorKeepsOnlyItsAdviceTests: XCTestCase {

    /// Enough nodes for a per-node cost to be a reading rather than noise, few
    /// enough that the case costs about a second.
    private static let files = 20_000

    /// A flat tree of files the advisor will judge and decline to advise.
    ///
    /// Old enough to reach the age test and small enough to fail both size
    /// floors, which is the ordinary case on a real volume: the sweep asks the
    /// removal gate about every one of them and produces nothing.
    private func judgedTree() -> DiskNode {
        let children = (0..<Self.files).map {
            DiskNode(name: "f\($0).bin", bytes: 1_000, isDirectory: false,
                     modified: 1_000_000)
        }
        return DiskNode(name: "r", bytes: 1_000 * Self.files, isDirectory: true,
                        children: children)
    }

    func testTheSweepDoesNotKeepEveryPathItAskedTheGateAbout() throws {
        let tree = judgedTree()
        // The allocator keeps its tools out, so the first pass pays for whatever
        // Foundation warms up once and the reading is the second.
        _ = autoreleasepool { DiskAdvisor.advise(root: tree, rootPath: "/r", home: "/Users/me") }

        let before = AllocatorBooks.allocatedBytes()
        let advice = DiskAdvisor.advise(root: tree, rootPath: "/r", home: "/Users/me")
        let after = AllocatorBooks.allocatedBytes()

        // Said out loud: a sweep that visited nothing would divide a small
        // difference by a large number and pass whatever the loop did.
        XCTAssertTrue(advice.isEmpty, "the fixture was meant to produce no advice")
        let perNode = Double(after - before) / Double(Self.files)
        print(String(format: "advised over %d nodes: malloc grew %.1f MB (%.0f bytes/node)",
                     Self.files, Double(after - before) / 1_048_576, perNode))

        // The control, and it is what makes the reading mean anything: the same
        // call with a pool around it, so whatever the sweep autoreleased is
        // drained before the second reading is taken.
        let pooled0 = AllocatorBooks.allocatedBytes()
        autoreleasepool { _ = DiskAdvisor.advise(root: tree, rootPath: "/r", home: "/Users/me") }
        let pooled1 = AllocatorBooks.allocatedBytes()
        print(String(format: "the same sweep inside a pool: %.1f MB (%.0f bytes/node)",
                     Double(pooled1 - pooled0) / 1_048_576,
                     Double(pooled1 - pooled0) / Double(Self.files)))

        // **The threshold sits between two measurements of this fixture**, three
        // consecutive runs each on the machine this was written on:
        //
        //     sweep as it stands:                     56 bytes/node (1.1 MB)
        //     the same sweep with a pool inside it:    0 bytes/node (0.0 MB)
        //
        // 25 fails the defect by more than a factor of two and passes the repair
        // by the whole of it. A number above 56 would have recorded the present
        // rather than guarded it.
        XCTAssertLessThan(perNode, 25, """
            the advisor is keeping every path it judged rather than the advice it produced. \
            `DiskAdvisor.sweep` asks `UserFileScope.isRemovable` per file node, and nothing \
            drains what Foundation hands back until the whole scan returns — the pool goes \
            inside the sweep.
            """)
    }
}
