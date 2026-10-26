import XCTest
@testable import Module_Disk_Engine

/// The inputs a tester reaches for first: nothing, one, enormous, negative,
/// duplicated, and named in a way that breaks string handling. Every crash
/// this module has shipped came from a value someone assumed could not occur —
/// a negative device id, a path joined onto "/", a folder with no bytes.
final class AdversarialInputTests: XCTestCase {
    // MARK: - Tree building

    func testTheSameFileTwiceIsCountedOnce() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1)
        builder.addFile(path: "/r/a.bin", bytes: 100, fileID: 7)
        builder.addFile(path: "/r/hardlink.bin", bytes: 100, fileID: 7)
        XCTAssertEqual(builder.build().bytes, 100)
    }

    func testNamesThatBreakPathHandling() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1)
        for name in ["with space.bin", "с кириллицей.bin", "emoji 🙂.bin",
                     "dots...bin", "…", "tab\tname.bin"] {
            builder.addFile(path: "/r/" + name, bytes: 10, fileID: UInt64(abs(name.hashValue)))
        }
        let root = builder.build()
        XCTAssertEqual(root.bytes, 60)
        // Asked of the snapshot rather than the node: the path is composed on the
        // way out now, so the string worth checking is the one the UI receives.
        let entry = DiskEntry(root, depth: 2, path: "/r")
        XCTAssertTrue(entry.children.allSatisfy { $0.path.hasPrefix("/r/") },
                      "\(entry.children.map(\.path))")
    }

    /// A file directly at the volume root, where the parent is "/" itself.
    func testFileAtTheVolumeRoot() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1)
        builder.addFile(path: "/lonely.bin", bytes: 42, fileID: 1)
        let root = builder.build()
        XCTAssertEqual(root.bytes, 42)
        XCTAssertEqual(DiskEntry(root, depth: 2, path: "/").children.first?.path,
                       "/lonely.bin", "the root already ends in a slash")
    }

    func testDeeplyNestedPath() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1)
        let deep = "/r/" + (0..<60).map { "d\($0)" }.joined(separator: "/") + "/file.bin"
        builder.addFile(path: deep, bytes: 5, fileID: 1)
        XCTAssertEqual(builder.build().bytes, 5)
    }

    // MARK: - Pruning

    func testPruningEveryChildLeavesTheRootStanding() {
        let tree = DiskEntry(name: "r", path: "/r", bytes: 30, isDirectory: true, noAccess: false,
                             children: [
                                DiskEntry(name: "a", path: "/r/a", bytes: 20, isDirectory: false,
                                          noAccess: false, children: []),
                                DiskEntry(name: "b", path: "/r/b", bytes: 10, isDirectory: false,
                                          noAccess: false, children: []),
                             ])
        let pruned = DiskTreePrune.removing(paths: ["/r/a", "/r/b"], from: tree)
        XCTAssertTrue(pruned.children.isEmpty)
        XCTAssertEqual(pruned.bytes, 0)
    }

    /// Removing the same path twice must not subtract its bytes twice.
    func testDuplicatePathsInOneRemoval() {
        let tree = DiskEntry(name: "r", path: "/r", bytes: 30, isDirectory: true, noAccess: false,
                             children: [DiskEntry(name: "a", path: "/r/a", bytes: 20,
                                                  isDirectory: false, noAccess: false,
                                                  children: [])])
        let pruned = DiskTreePrune.removing(paths: ["/r/a", "/r/a"], from: tree)
        XCTAssertEqual(pruned.bytes, 10)
    }

    // MARK: - Focus

    private var freshRoot: DiskEntry {
        DiskEntry(name: "r", path: "/r", bytes: 1, isDirectory: true, noAccess: false, children: [])
    }

    func testFocusSurvivesAFolderVanishingMidScan() {
        let fresh = freshRoot
        // The user had drilled into /r/gone, which the final tree does not have.
        let resolved = DiskFocus.resolve(paths: ["/r", "/r/gone", "/r/gone/deeper"], in: fresh)
        XCTAssertEqual(resolved.map(\.path), ["/r"])
    }

    func testFocusOnAnEmptyPathListFallsBackToTheRoot() {
        XCTAssertEqual(DiskFocus.resolve(paths: [], in: freshRoot).map(\.path), ["/r"])
    }
}
