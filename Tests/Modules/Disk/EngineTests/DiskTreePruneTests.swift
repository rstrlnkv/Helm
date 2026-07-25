import XCTest
@testable import Module_Disk_Engine

/// Trashing a folder invalidates the tree — but re-walking a whole disk to
/// learn something we already know (those bytes are gone) costs a minute.
/// Pruning applies the deletion to the tree we have.
final class DiskTreePruneTests: XCTestCase {
    private func entry(_ path: String, _ bytes: Int, _ children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                  isDirectory: !children.isEmpty, noAccess: false, children: children)
    }

    private var tree: DiskEntry {
        entry("/root", 1000, [
            entry("/root/a", 700, [
                entry("/root/a/big", 500),
                entry("/root/a/small", 200),
            ]),
            entry("/root/b", 300),
        ])
    }

    func testRemovedNodeDisappearsAndAncestorsShrink() {
        let pruned = DiskTreePrune.removing(paths: ["/root/a/big"], from: tree)
        let a = pruned.children.first { $0.name == "a" }!
        XCTAssertEqual(a.children.map(\.name), ["small"])
        XCTAssertEqual(a.bytes, 200)
        XCTAssertEqual(pruned.bytes, 500)
    }

    func testRemovingAWholeSubtreeDropsItsChildrenToo() {
        let pruned = DiskTreePrune.removing(paths: ["/root/a"], from: tree)
        XCTAssertEqual(pruned.children.map(\.name), ["b"])
        XCTAssertEqual(pruned.bytes, 300)
    }

    func testSeveralPathsAtOnce() {
        let pruned = DiskTreePrune.removing(paths: ["/root/a/small", "/root/b"], from: tree)
        XCTAssertEqual(pruned.bytes, 500)
        XCTAssertEqual(pruned.children.map(\.name), ["a"])
    }

    /// A path that is already gone (or was never in this tree) changes nothing.
    func testUnknownPathIsIgnored() {
        let pruned = DiskTreePrune.removing(paths: ["/root/nope"], from: tree)
        XCTAssertEqual(pruned, tree)
    }

    func testEmptyRemovalReturnsTheSameTree() {
        XCTAssertEqual(DiskTreePrune.removing(paths: [], from: tree), tree)
    }

    /// Removing the root itself would leave nothing to show; the tree stands.
    func testRootCannotBePruned() {
        XCTAssertEqual(DiskTreePrune.removing(paths: ["/root"], from: tree), tree)
    }
}
