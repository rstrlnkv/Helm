import XCTest
@testable import Module_Disk_Engine

/// Grafting a measured folder back into the tree, without disturbing the rest.
final class DiskTreeSpliceTests: XCTestCase {
    private func entry(_ path: String, _ bytes: Int = 1,
                       _ children: [DiskEntry] = []) -> DiskEntry {
        DiskEntry(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                  isDirectory: true, noAccess: false, children: children)
    }

    private var tree: DiskEntry {
        entry("/a", 10, [entry("/a/b", 5, [entry("/a/b/c")]), entry("/a/d", 5)])
    }

    func testTheMeasuredFolderTakesItsPlace() {
        let measured = entry("/a/b/c", 99, [entry("/a/b/c/deep")])
        let result = DiskTreeSplice.replacing("/a/b/c", with: measured, in: tree)
        let spliced = result.children.first { $0.path == "/a/b" }?
            .children.first { $0.path == "/a/b/c" }
        XCTAssertEqual(spliced?.children.map(\.path), ["/a/b/c/deep"])
        XCTAssertEqual(spliced?.bytes, 99)
    }

    /// Everything outside the branch is the tree that was already there.
    func testTheRestOfTheTreeIsUntouched() {
        let result = DiskTreeSplice.replacing("/a/b/c", with: entry("/a/b/c", 99), in: tree)
        XCTAssertEqual(result.children.first { $0.path == "/a/d" }?.bytes, 5)
        XCTAssertEqual(result.path, "/a")
    }

    func testReplacingTheRootIsTheNewTree() {
        let measured = entry("/a", 42)
        XCTAssertEqual(DiskTreeSplice.replacing("/a", with: measured, in: tree).bytes, 42)
    }

    /// A path that is not in this tree leaves it exactly as it was — including
    /// a namesake that merely shares a prefix.
    func testAnUnrelatedPathChangesNothing() {
        XCTAssertEqual(DiskTreeSplice.replacing("/zz", with: entry("/zz", 9), in: tree), tree)
        XCTAssertEqual(DiskTreeSplice.replacing("/a/bc", with: entry("/a/bc", 9), in: tree), tree)
    }
}
