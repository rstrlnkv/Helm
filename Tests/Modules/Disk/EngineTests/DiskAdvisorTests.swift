import XCTest
@testable import Module_Disk_Engine

final class DiskAdvisorTests: XCTestCase {
    private let home = "/Users/test"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ path: String, _ bytes: Int, ageDays: Double = 0) -> DiskNode {
        DiskNode(name: (path as NSString).lastPathComponent, path: path, bytes: bytes,
                 isDirectory: false,
                 modified: now.timeIntervalSince1970 - ageDays * 86_400)
    }

    private func dir(_ path: String, _ children: [DiskNode]) -> DiskNode {
        DiskNode(name: (path as NSString).lastPathComponent, path: path,
                 bytes: children.reduce(0) { $0 + $1.bytes }, isDirectory: true,
                 children: children)
    }

    // MARK: - Caches

    func testKnownCacheFolderAboveThresholdIsAdvised() {
        let derived = dir(home + "/Library/Developer/Xcode/DerivedData",
                          [file(home + "/Library/Developer/Xcode/DerivedData/big.o",
                                2_000_000_000)])
        let root = dir(home, [dir(home + "/Library",
                                  [dir(home + "/Library/Developer",
                                       [dir(home + "/Library/Developer/Xcode", [derived])])])])
        let advice = DiskAdvisor.advise(root: root, home: home, now: now)
        XCTAssertTrue(advice.contains { $0.path == derived.path && $0.kind == .cache })
    }

    func testSmallCacheFolderIsNotAdvised() {
        let caches = dir(home + "/Library/Caches",
                         [file(home + "/Library/Caches/tiny", 1_000_000)])
        let root = dir(home, [dir(home + "/Library", [caches])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, home: home, now: now).isEmpty)
    }

    // MARK: - Old downloads

    func testOldBigDownloadIsAdvised() {
        let old = file(home + "/Downloads/installer.dmg", 900_000_000, ageDays: 90)
        let fresh = file(home + "/Downloads/today.zip", 900_000_000, ageDays: 1)
        let root = dir(home, [dir(home + "/Downloads", [old, fresh])])
        let advice = DiskAdvisor.advise(root: root, home: home, now: now)
        XCTAssertTrue(advice.contains { $0.path == old.path && $0.kind == .oldDownload })
        XCTAssertFalse(advice.contains { $0.path == fresh.path })
    }

    // MARK: - Large & old files

    func testLargeOldFileAnywhereIsAdvised() {
        let stale = file(home + "/Movies/raw-footage.mov", 5_000_000_000, ageDays: 400)
        let root = dir(home, [dir(home + "/Movies", [stale])])
        let advice = DiskAdvisor.advise(root: root, home: home, now: now)
        XCTAssertTrue(advice.contains { $0.path == stale.path && $0.kind == .largeOld })
    }

    func testLargeFileWithUnknownDateIsNotAdvised() {
        // modified == 0 means the scanner had no date; never guess "old".
        let unknown = DiskNode(name: "blob", path: home + "/Movies/blob", bytes: 5_000_000_000,
                               isDirectory: false)
        let root = dir(home, [dir(home + "/Movies", [unknown])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, home: home, now: now).isEmpty)
    }

    func testProtectedPathsAreNeverAdvised() {
        let sys = file("/System/Library/huge.bin", 9_000_000_000, ageDays: 900)
        let root = dir("/", [dir("/System", [dir("/System/Library", [sys])])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, home: home, now: now).isEmpty)
    }

    // MARK: - Dedup, order, cap

    func testFileInsideAdvisedCacheIsNotAdvisedTwice() {
        let inner = file(home + "/Library/Caches/huge.dat", 3_000_000_000, ageDays: 400)
        let caches = dir(home + "/Library/Caches", [inner])
        let root = dir(home, [dir(home + "/Library", [caches])])
        let advice = DiskAdvisor.advise(root: root, home: home, now: now)
        XCTAssertEqual(advice.count, 1)
        XCTAssertEqual(advice.first?.kind, .cache)
    }

    func testSortedByBytesDescendingAndCapped() {
        var children: [DiskNode] = []
        for i in 0..<30 {
            children.append(file(home + "/Movies/clip\(i).mov",
                                 1_500_000_000 + i * 1_000_000, ageDays: 300))
        }
        let root = dir(home, [dir(home + "/Movies", children)])
        let advice = DiskAdvisor.advise(root: root, home: home, now: now)
        XCTAssertEqual(advice.count, 12)
        XCTAssertEqual(advice.map(\.bytes), advice.map(\.bytes).sorted(by: >))
    }

    func testFoldedBucketIsNeverAdvised() {
        let bucket = file(home + "/Movies/…", 8_000_000_000, ageDays: 500)
        let root = dir(home, [dir(home + "/Movies", [bucket])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, home: home, now: now).isEmpty)
    }
}
