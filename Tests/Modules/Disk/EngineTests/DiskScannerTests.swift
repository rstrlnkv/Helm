import XCTest
@testable import Module_Disk_Engine

/// Against a real fixture tree in tmp — the bulk-attribute walk has too many
/// byte-layout edge cases to trust without touching an actual filesystem.
final class DiskScannerTests: XCTestCase {
    private var fixture: URL!

    override func setUpWithError() throws {
        fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-disk-test-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: fixture.appendingPathComponent("sub/deeper"),
                               withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: fixture.appendingPathComponent("big.bin"))
        try Data(count: 50_000).write(to: fixture.appendingPathComponent("sub/mid.bin"))
        try Data(count: 60_000).write(to: fixture.appendingPathComponent("sub/deeper/deep.bin"))
        // A symlink whose target must NOT be counted or followed.
        try fm.createSymbolicLink(at: fixture.appendingPathComponent("link"),
                                  withDestinationURL: fixture.appendingPathComponent("sub"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fixture)
    }

    func testScanFindsFilesAndRollsUpSizes() throws {
        let root = DiskScanner(foldThreshold: 0).scan(root: fixture.path)
        let tree = try XCTUnwrap(root)
        // Allocated size ≥ logical size; every file present exactly once.
        XCTAssertGreaterThanOrEqual(tree.bytes, 210_000)
        XCTAssertLessThan(tree.bytes, 400_000)   // and no double counting
        let sub = tree.children.first { $0.name == "sub" }
        XCTAssertNotNil(sub)
        XCTAssertGreaterThanOrEqual(sub!.bytes, 110_000)
        let deeper = sub!.children.first { $0.name == "deeper" }
        XCTAssertNotNil(deeper)
    }

    func testSymlinkTargetIsNotDoubleCounted() throws {
        let tree = try XCTUnwrap(DiskScanner(foldThreshold: 0).scan(root: fixture.path))
        // If the link were followed, sub's 110KB would be charged twice.
        XCTAssertLessThan(tree.bytes, 330_000)
        XCTAssertNil(tree.children.first { $0.name == "link" })
    }

    func testCancelReturnsNil() throws {
        let scanner = DiskScanner(foldThreshold: 0)
        scanner.cancel()
        XCTAssertNil(scanner.scan(root: fixture.path))
    }

    func testProgressReportsArrive() throws {
        final class Box: @unchecked Sendable { var last: ScanProgress? }
        let box = Box()
        _ = DiskScanner(foldThreshold: 0).scan(root: fixture.path) { box.last = $0 }
        let last = try XCTUnwrap(box.last)
        XCTAssertEqual(last.filesSeen, 3)
        XCTAssertGreaterThanOrEqual(last.bytesSeen, 210_000)
    }

    /// MODTIME sits between OBJTYPE and FILEID in attribute-bit order; a
    /// misparse here silently corrupts every field after it.
    func testScannerReadsModificationDates() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("helm-mtime-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("old.bin")
        try Data(count: 200_000).write(to: file)
        let past = Date(timeIntervalSinceNow: -400 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path)

        let root = try XCTUnwrap(DiskScanner(foldThreshold: 1).scan(root: dir.path))
        let node = try XCTUnwrap(root.children.first { $0.name == "old.bin" })
        XCTAssertEqual(node.modified, past.timeIntervalSince1970, accuracy: 2)
        XCTAssertEqual(node.bytes > 0, true)
    }
}
