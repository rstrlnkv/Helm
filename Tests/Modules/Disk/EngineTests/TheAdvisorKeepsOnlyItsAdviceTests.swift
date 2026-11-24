import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Disk_Engine

/// What the sweep at the end of a scan costs the process.
///
/// `DiskAdvisor.sweep` asks `UserFileScope.isRemovable` about each file past the
/// size and age floors, and that gate hands back autoreleased Foundation objects.
/// The sweep runs on the scan's own thread inside `offTheCooperativePool`, so
/// without a pool inside the sweep everything it judged would live until the
/// whole scan returns (Architecture/ModulePattern.md § Bulk reads).
///
/// Measured against the allocator's books rather than `MemoryFootprint.current()`
/// (Architecture/DiagnosticsLog.md § The memory trail).
final class TheAdvisorKeepsOnlyItsAdviceTests: XCTestCase {

    /// Enough nodes for a per-node cost to be a reading rather than noise, few
    /// enough that the case costs about a second.
    private static let files = 20_000

    private let home = NSHomeDirectory()
    private let old = Date().timeIntervalSince1970 - 400 * 86_400

    /// A flat tree of files the advisor will judge and decline to advise, and one
    /// file in Downloads it will advise.
    ///
    /// The flat files are big and old enough to pass the cheap size and age
    /// floors the sweep judges before the gate, outside Downloads and under the
    /// large-file floor, so each reaches the removal gate and produces nothing.
    /// The Downloads file is the witness that the gate is reached and says yes:
    /// a sweep that never asked it would leave no advice.
    private func judgedTree() -> DiskNode {
        let children = (0..<Self.files).map {
            DiskNode(name: "f\($0).bin", bytes: 100_000_000, isDirectory: false,
                     modified: old)
        }
        let witness = DiskNode(name: "Downloads", bytes: 100_000_000, isDirectory: true,
                               children: [DiskNode(name: "witness.bin", bytes: 100_000_000,
                                                   isDirectory: false, modified: old)])
        return DiskNode(name: "r", bytes: 100_000_000 * (Self.files + 1), isDirectory: true,
                        children: children + [witness])
    }

    func testTheSweepDoesNotKeepEveryPathItAskedTheGateAbout() throws {
        let tree = judgedTree()
        // The allocator keeps its tools out, so the first pass pays for whatever
        // Foundation warms up once and the reading is the second.
        _ = autoreleasepool { DiskAdvisor.advise(root: tree, rootPath: home, home: home) }

        let before = AllocatorBooks.allocatedBytes()
        let advice = DiskAdvisor.advise(root: tree, rootPath: home, home: home)
        let after = AllocatorBooks.allocatedBytes()

        // Said out loud: a sweep that never asked the gate would divide a small
        // difference by a large number and pass whatever the loop did.
        XCTAssertEqual(advice.map(\.name), ["witness.bin"],
                       "the gate was not reached, or the fixture advises more than its witness")
        let perNode = Double(after - before) / Double(Self.files)
        print(String(format: "advised over %d nodes: malloc grew %.1f MB (%.0f bytes/node)",
                     Self.files, Double(after - before) / 1_048_576, perNode))

        // The control, and it is what makes the reading mean anything: the same
        // call with a pool around it, so whatever the sweep autoreleased is
        // drained before the second reading is taken.
        let pooled0 = AllocatorBooks.allocatedBytes()
        autoreleasepool { _ = DiskAdvisor.advise(root: tree, rootPath: home, home: home) }
        let pooled1 = AllocatorBooks.allocatedBytes()
        print(String(format: "the same sweep inside a pool: %.1f MB (%.0f bytes/node)",
                     Double(pooled1 - pooled0) / 1_048_576,
                     Double(pooled1 - pooled0) / Double(Self.files)))

        // The threshold sits between the two readings the lines above print:
        // about 88 bytes/node with the pool taken out of `sweep`, 0 with it in.
        XCTAssertLessThan(perNode, 25, """
            the advisor is keeping every path it judged rather than the advice it produced. \
            `DiskAdvisor.sweep` asks `UserFileScope.isRemovable` for each file that passes the size and age floors, and nothing \
            drains what Foundation hands back until the whole scan returns — the pool goes \
            inside the sweep.
            """)
    }
}
