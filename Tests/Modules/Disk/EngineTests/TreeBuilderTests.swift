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

    /// Zero is not an id, it is the absence of one: `getattrlistbulk` leaves
    /// `fileID` at 0 when the filesystem does not return `ATTR_CMN_FILEID`
    /// (`DiskScanner.readDirectory`). Deduplicated like any other id, the first
    /// such file was counted and every later one vanished from the tree **and
    /// from the totals** — a whole volume reported as one file.
    ///
    /// Nobody here could name a volume that withholds the attribute, so this is
    /// a guard rather than a fix for a reproduction: what it pins is that 0
    /// means "unknown", not "the same file again".
    func testFilesWithNoIdAreAllCounted() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.addFile(path: "/scan/a/one", bytes: 100, fileID: 0)
        builder.addFile(path: "/scan/a/two", bytes: 50, fileID: 0)
        builder.addFile(path: "/scan/a/three", bytes: 25, fileID: 0)
        let root = builder.build()
        XCTAssertEqual(root.children.first { $0.name == "a" }?.children.map(\.name).sorted(),
                       ["one", "three", "two"],
                       "files with no id were taken for one another and dropped")
        XCTAssertEqual(root.bytes, 175, "and their bytes went with them")
    }

    /// The control: a real id still means the same file, whatever it is called.
    /// Without this the rule above is satisfied by never deduplicating at all.
    func testARealIdStillCountsOnceHoweverManyNamesItHas() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.addFile(path: "/scan/a/original", bytes: 500, fileID: 42)
        builder.addFile(path: "/scan/b/link", bytes: 500, fileID: 42)
        XCTAssertEqual(builder.build().bytes, 500)
    }

    /// `directory(for:)` walks toward `/` and its only base case is finding the
    /// root in its index. `/`'s parent is `/`, so a path from outside the scan
    /// root recurses until the stack is gone. Every caller descends from the
    /// root, so this is unreachable today — and a guard costs nothing, which is
    /// less than the crash costs.
    func testAPathFromOutsideTheRootDoesNotRecurseForever() {
        let builder = TreeBuilder(root: "/scan", foldThreshold: 0)
        builder.markNoAccess(path: "/elsewhere/deep")
        builder.addFile(path: "/scan/a/one", bytes: 100, fileID: 1)
        let root = builder.build()
        XCTAssertEqual(root.bytes, 100, "the scan's own tree is unharmed")
        // Terminating by charging everything to the root would trade the crash
        // for a lie: a folder that was never scanned cannot make the volume
        // unreadable, and the ring would draw the whole disk flagged.
        XCTAssertFalse(root.noAccess, "a path outside the scan flagged the scan root")
        XCTAssertTrue(root.children.map(\.name) == ["a"],
                      "and it invented no folders: \(root.children.map(\.name))")
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

    /// The bucket under "/" must be "/…", not "//…": doubled slashes break
    /// every path comparison downstream.
    func testFoldedBucketAtRootHasASingleSlash() {
        let builder = TreeBuilder(root: "/", foldThreshold: 1_000)
        builder.addFile(path: "/tiny.bin", bytes: 10, fileID: 1)
        let bucket = builder.build().children.first { $0.name == "…" }
        XCTAssertEqual(bucket?.path, "/…")
    }
}
