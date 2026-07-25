import XCTest
@testable import Module_Disk_Engine

final class TreeBuilderTests: XCTestCase {
    func testDirectorySizesRollUp() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.addFile(path: "/scan/a/one", bytes: 100, fileID: 1)
        builder.addFile(path: "/scan/a/two", bytes: 50, fileID: 2)
        builder.addFile(path: "/scan/b/three", bytes: 25, fileID: 3)
        let root = builder.build()
        XCTAssertEqual(root.bytes, 175)
        let a = root.children.first { $0.name == "a" }!
        XCTAssertEqual(a.bytes, 150)
        XCTAssertEqual(a.children.count, 2)
    }

    /// The same inode reachable twice must be charged once — hard links made
    /// naive scanners report double the truth.
    func testHardLinksCountedOnce() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.addFile(path: "/scan/a/original", bytes: 500, fileID: 42)
        builder.addFile(path: "/scan/b/link", bytes: 500, fileID: 42)
        let root = builder.build()
        XCTAssertEqual(root.bytes, 500)
    }

    /// Files smaller than the threshold collapse into their parent's "small
    /// files" accounting instead of becoming nodes — memory stays bounded.
    func testSmallFilesFoldIntoParent() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 10)
        builder.addFile(path: "/scan/a/big", bytes: 100, fileID: 1)
        for i in 0..<20 { builder.addFile(path: "/scan/a/small\(i)", bytes: 1, fileID: UInt64(10 + i)) }
        let root = builder.build()
        let a = root.children.first { $0.name == "a" }!
        XCTAssertEqual(a.bytes, 120)                       // nothing lost
        XCTAssertEqual(a.children.count, 2)                // big + folded bucket
        let folded = a.children.first { $0.name == "…" }!
        XCTAssertEqual(folded.bytes, 20)
    }

    func testUnreadableDirectoryIsFlagged() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.addFile(path: "/scan/ok/file", bytes: 10, fileID: 1)
        builder.markNoAccess(path: "/scan/secret")
        let root = builder.build()
        let secret = root.children.first { $0.name == "secret" }!
        XCTAssertTrue(secret.noAccess)
        XCTAssertEqual(secret.bytes, 0)
    }

    /// Deep paths create intermediate directories on demand.
    func testIntermediateDirectoriesAppear() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.addFile(path: "/scan/x/y/z/file", bytes: 7, fileID: 1)
        let root = builder.build()
        XCTAssertEqual(root.children.first?.name, "x")
        XCTAssertEqual(root.children.first?.children.first?.name, "y")
    }
}
