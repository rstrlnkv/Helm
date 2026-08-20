import XCTest
@testable import Module_Disk_Engine

final class DiskAdvisorTests: XCTestCase {
    private let home = "/Users/test"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ path: String, _ bytes: Int, ageDays: Double = 0) -> DiskNode {
        DiskNode(name: (path as NSString).lastPathComponent, bytes: bytes,
                 isDirectory: false,
                 modified: now.timeIntervalSince1970 - ageDays * 86_400)
    }

    private func dir(_ path: String, _ children: [DiskNode]) -> DiskNode {
        DiskNode(name: (path as NSString).lastPathComponent,
                 bytes: children.reduce(0) { $0 + $1.bytes }, isDirectory: true,
                 children: children)
    }

    // MARK: - Caches

    func testKnownCacheFolderAboveThresholdIsAdvised() {
        let derivedPath = home + "/Library/Developer/Xcode/DerivedData"
        let derived = dir(derivedPath, [file(derivedPath + "/big.o", 2_000_000_000)])
        let root = dir(home, [dir(home + "/Library",
                                  [dir(home + "/Library/Developer",
                                       [dir(home + "/Library/Developer/Xcode", [derived])])])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        // Against the path the fixture was built from: the node knows only its
        // name, so the advisor composing the same string back is the assertion.
        XCTAssertTrue(advice.contains { $0.path == derivedPath && $0.kind == .cache },
                      "\(advice.map { "\($0.path)=\($0.kind)" })")
    }

    func testSmallCacheFolderIsNotAdvised() {
        let caches = dir(home + "/Library/Caches",
                         [file(home + "/Library/Caches/tiny", 1_000_000)])
        let root = dir(home, [dir(home + "/Library", [caches])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now).isEmpty)
    }

    /// macOS carries an ACL on `~/Library/Caches` — `group:everyone deny
    /// delete` — that its children do not, so `trashItem` refuses the folder
    /// and takes any of its contents happily. The row offered the folder, the
    /// press produced NSCocoaErrorDomain 513, and Recommendations had
    /// recommended the one thing it could not do.
    func testCacheAdviceNamesTheContentsAndNeverTheContainer() {
        let cachesPath = home + "/Library/Caches"
        let caches = dir(cachesPath, [file(cachesPath + "/Firefox", 3_000_000_000),
                                      file(cachesPath + "/Adobe", 900_000_000)])
        let root = dir(home, [dir(home + "/Library", [caches])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        let cache = advice.first { $0.kind == .cache }
        XCTAssertEqual(cache?.path, cachesPath, "the row still names the folder")
        XCTAssertEqual(cache?.targets.map(\.path).sorted(),
                       [cachesPath + "/Adobe", cachesPath + "/Firefox"])
        XCTAssertFalse(cache?.targets.contains { $0.path == cachesPath } ?? true,
                       "the container is what macOS refuses; it must not be a target")
    }

    /// One row, one size, one button — whatever the expansion costs behind it.
    func testExpandedCacheIsStillASingleRow() {
        let cachesPath = home + "/Library/Caches"
        let children = (0..<40).map { file(cachesPath + "/app\($0)", 30_000_000) }
        let root = dir(home, [dir(home + "/Library", [dir(cachesPath, children)])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.count, 1)
        XCTAssertEqual(advice.first?.name, "Caches")
    }

    /// The folded bucket is an aggregate, not a path, and its own flag is what
    /// says so — nothing will ever be attempted for it. Its bytes belong to the
    /// folder's total and not to the row's promise.
    func testCacheSizeIsWhatWillBeAttempted() {
        let cachesPath = home + "/Library/Caches"
        let loose = DiskNode(name: "…", bytes: 400_000_000, isDirectory: false, isFolded: true)
        let caches = dir(cachesPath, [file(cachesPath + "/Firefox", 3_000_000_000), loose])
        let root = dir(home, [dir(home + "/Library", [caches])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.first?.bytes, 3_000_000_000)
        XCTAssertEqual(advice.first?.targets.map(\.path), [cachesPath + "/Firefox"])
    }

    /// And the threshold judges the same figure the row shows. A folder holding
    /// nothing but small loose files is 400 MB of cache that pressing + cannot
    /// touch, so it is not a recommendation.
    func testCacheOfNothingButLooseFilesIsNotAdvised() {
        let cachesPath = home + "/Library/Caches"
        let loose = DiskNode(name: "…", bytes: 400_000_000, isDirectory: false, isFolded: true)
        let root = dir(home, [dir(home + "/Library", [dir(cachesPath, [loose])])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, rootPath: home, home: home,
                                         now: now).isEmpty)
    }

    /// Every advice, of every kind, promises exactly what it will attempt. The
    /// structural version of the size question, so a third kind cannot be added
    /// with a size that means something else.
    func testEveryAdviceWeighsItsOwnTargets() {
        let cachesPath = home + "/Library/Caches"
        let root = dir(home, [
            dir(home + "/Library", [dir(cachesPath, [file(cachesPath + "/Firefox", 3_000_000_000)])]),
            dir(home + "/Downloads", [file(home + "/Downloads/installer.dmg",
                                           900_000_000, ageDays: 90)]),
            dir(home + "/Movies", [file(home + "/Movies/raw.mov", 5_000_000_000, ageDays: 400)]),
        ])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.count, 3)
        for item in advice {
            XCTAssertFalse(item.targets.isEmpty, item.path)
            XCTAssertEqual(item.bytes, item.targets.reduce(0) { $0 + $1.bytes }, item.path)
        }
    }

    // MARK: - Old downloads

    func testOldBigDownloadIsAdvised() {
        let oldPath = home + "/Downloads/installer.dmg"
        let freshPath = home + "/Downloads/today.zip"
        let root = dir(home, [dir(home + "/Downloads",
                                  [file(oldPath, 900_000_000, ageDays: 90),
                                   file(freshPath, 900_000_000, ageDays: 1)])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertTrue(advice.contains { $0.path == oldPath && $0.kind == .oldDownload })
        XCTAssertFalse(advice.contains { $0.path == freshPath })
    }

    // MARK: - Large & old files

    func testLargeOldFileAnywhereIsAdvised() {
        let stalePath = home + "/Movies/raw-footage.mov"
        let root = dir(home, [dir(home + "/Movies", [file(stalePath, 5_000_000_000, ageDays: 400)])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertTrue(advice.contains { $0.path == stalePath && $0.kind == .largeOld })
    }

    func testLargeFileWithUnknownDateIsNotAdvised() {
        // modified == 0 means the scanner had no date; never guess "old".
        let unknown = DiskNode(name: "blob", bytes: 5_000_000_000, isDirectory: false)
        let root = dir(home, [dir(home + "/Movies", [unknown])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now).isEmpty)
    }

    // MARK: - The date the advice was judged by

    /// The row asks somebody to bin a gigabyte-plus file and gives a category
    /// word as its whole reason. The date it was judged by is the reason, and
    /// the advice carried no date at all — so the screen could not have shown
    /// one even if it wanted to.
    func testLargeOldAdviceCarriesTheDateItWasJudgedBy() {
        let stale = file(home + "/Movies/raw-footage.mov", 5_000_000_000, ageDays: 400)
        let root = dir(home, [dir(home + "/Movies", [stale])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.first?.modified, stale.modified)
    }

    func testOldDownloadAdviceCarriesTheDateItWasJudgedBy() {
        let old = file(home + "/Downloads/installer.dmg", 900_000_000, ageDays: 90)
        let root = dir(home, [dir(home + "/Downloads", [old])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.first?.modified, old.modified)
    }

    /// A folder's own modification time is when something was last added to it,
    /// not when anything in it was last written — so a cache advice has no date
    /// to offer and must not invent one.
    func testCacheAdviceCarriesNoDate() {
        let derived = dir(home + "/Library/Developer/Xcode/DerivedData",
                          [file(home + "/Library/Developer/Xcode/DerivedData/big.o",
                                2_000_000_000)])
        let root = dir(home, [dir(home + "/Library",
                                  [dir(home + "/Library/Developer",
                                       [dir(home + "/Library/Developer/Xcode", [derived])])])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.first?.kind, .cache)
        XCTAssertNil(advice.first?.modified)
    }

    /// A scan cached by an earlier build has no such key, and the whole cached
    /// tree is decoded or dropped as one — a required field here would throw
    /// somebody's last scan away on the first launch after an update.
    func testAdviceCachedByAnEarlierBuildStillDecodes() throws {
        let json = Data("""
            {"name":"blob","path":"/Users/test/Movies/blob","bytes":5000000000,"kind":"largeOld"}
            """.utf8)
        let advice = try JSONDecoder().decode(DiskAdvice.self, from: json)
        XCTAssertNil(advice.modified)
        XCTAssertEqual(advice.kind, .largeOld)
    }

    /// The one fixture rooted at the volume rather than at home, which is what
    /// the app actually scans — and the reason `rootPath` is a parameter of its
    /// own. Pair this tree with `home` as its root and the composed path becomes
    /// `/Users/test/System/Library/huge.bin`, which `UserFileScope` allows,
    /// because it is inside a home directory. The protection this test is named
    /// for holds only while the composed path is the real one.
    func testProtectedPathsAreNeverAdvised() {
        let sys = file("/System/Library/huge.bin", 9_000_000_000, ageDays: 900)
        let root = dir("/", [dir("/System", [dir("/System/Library", [sys])])])
        let advice = DiskAdvisor.advise(root: root, rootPath: "/", home: home, now: now)
        XCTAssertTrue(advice.isEmpty, "\(advice.map(\.path))")
    }

    // MARK: - Dedup, order, cap

    func testFileInsideAdvisedCacheIsNotAdvisedTwice() {
        let inner = file(home + "/Library/Caches/huge.dat", 3_000_000_000, ageDays: 400)
        let caches = dir(home + "/Library/Caches", [inner])
        let root = dir(home, [dir(home + "/Library", [caches])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
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
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.count, 12)
        XCTAssertEqual(advice.map(\.bytes), advice.map(\.bytes).sorted(by: >))
    }

    /// By the flag. The fixture used to be an ordinary node wearing the name
    /// `…`, and it passed because `UserFileScope` refused that name — so the
    /// same test would have passed with `sweep`'s `!node.isFolded` deleted,
    /// which is the guard it exists to hold. The gate judges no names now.
    func testFoldedBucketIsNeverAdvised() {
        let bucket = DiskNode(name: "…", bytes: 8_000_000_000, isDirectory: false,
                              modified: now.timeIntervalSince1970 - 500 * 86_400,
                              isFolded: true)
        let root = dir(home, [dir(home + "/Movies", [bucket])])
        XCTAssertTrue(DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now).isEmpty)
    }

    /// And the other half of the same collision: a file the person really named
    /// `…` is an ordinary file, and big and old enough to be worth pointing at.
    /// Without this the assertion above is satisfied by a rule that refuses the
    /// name, which is what was wrong.
    func testAFileTheUserNamedLikeTheBucketIsAdvisedLikeAnyOther() {
        let real = file(home + "/Movies/…", 8_000_000_000, ageDays: 500)
        let root = dir(home, [dir(home + "/Movies", [real])])
        let advice = DiskAdvisor.advise(root: root, rootPath: home, home: home, now: now)
        XCTAssertEqual(advice.map(\.path), [home + "/Movies/…"])
    }
}
