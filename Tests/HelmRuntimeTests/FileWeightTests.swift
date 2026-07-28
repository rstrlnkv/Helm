import XCTest
@testable import HelmRuntime

/// `FileWeight` is the answer to "how many bytes does removing this give back",
/// and it has no tests of its own. Four callers depend on it — `HelmTrash`'s
/// freed total, the uninstaller's per-app size, Leftovers' row sizes and
/// Autopilot's size conditions — and the last of those decides whether an
/// unattended rule trashes a file.
///
/// Everything it is asked today is asked through one of those four, which means
/// the type's own edges are covered by whatever fixture the caller happened to
/// build. These are the edges.
final class FileWeightTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-weight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func write(_ relative: String, bytes: Int) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    // MARK: - The walk counts everything, once

    /// `UninstallerSizeArithmeticTests.testAHardLinkedFileIsMeasuredOnce`
    /// asserts `whole == one` over a folder holding exactly one allocation
    /// under two names. That equality is also what a walk which stopped after
    /// its first entry would produce. A third file, on its own inode, is what
    /// tells "counted once" from "counted one".
    func testAHardLinkIsCountedOnceAndTheOtherFilesAreStillCounted() throws {
        let payload = try write("Support/payload.bin", bytes: 400_000)
        try FileManager.default.linkItem(
            at: payload, to: root.appendingPathComponent("Support/payload-alias.bin"))
        try write("Support/other.bin", bytes: 200_000)

        let folder = root.appendingPathComponent("Support")
        let whole = FileWeight.allocated(of: folder)

        XCTAssertGreaterThanOrEqual(whole, 600_000,
                                    "600 KB of distinct allocation is in there; the walk "
                                    + "reports \(whole)")
        XCTAssertLessThan(whole, 800_000,
                          "the hard link's 400 KB was charged twice: \(whole)")
    }

    /// The batch form. `HelmTrash` threads one `seen` set through a whole
    /// basket, so two *separately basketed* names for one file must add up to
    /// one allocation — that is the difference between the ring's figure and
    /// the banner's.
    func testTwoNamesForOneFileInOneBatchAreOneAllocation() throws {
        let payload = try write("a.bin", bytes: 400_000)
        let alias = root.appendingPathComponent("b.bin")
        try FileManager.default.linkItem(at: payload, to: alias)

        var seen: Set<UInt64> = []
        let first = FileWeight.allocated(of: payload, countingOnce: &seen)
        let second = FileWeight.allocated(of: alias, countingOnce: &seen)

        XCTAssertGreaterThanOrEqual(first, 400_000)
        XCTAssertEqual(second, 0, "the second name frees nothing — the blocks stay")
    }

    /// …and a fresh set is a fresh question: the uninstaller measures one app
    /// at a time and must not have the previous app's inodes held against it.
    func testAFreshCallDoesNotInheritAnEarlierBatchesInodes() throws {
        let payload = try write("a.bin", bytes: 400_000)
        XCTAssertEqual(FileWeight.allocated(of: payload),
                       FileWeight.allocated(of: payload),
                       "asking twice gave two different answers")
    }

    // MARK: - Things that are not plain files

    /// A `.app` is a package, which `URLResourceValues` reports as *not* a
    /// directory. That is the case the type was written for: unwalked, it
    /// answers zero, and "smaller than 1 MB → Trash" then matches every
    /// application in a watched folder.
    func testAPackageIsWalkedRatherThanReportedAsNothing() throws {
        try write("Downloaded.app/Contents/MacOS/Downloaded", bytes: 4_000_000)
        let app = root.appendingPathComponent("Downloaded.app")
        let values = try app.resourceValues(forKeys: [.isPackageKey, .isDirectoryKey])

        XCTAssertEqual(values.isPackage, true, "precondition: the system calls this a package")
        XCTAssertGreaterThanOrEqual(FileWeight.allocated(of: app), 4_000_000)
    }

    /// Hidden files go with the folder, so they belong in the figure.
    func testHiddenFilesAreIncludedBecauseTheyAreFreedToo() throws {
        try write("box/.hidden.bin", bytes: 300_000)
        XCTAssertGreaterThanOrEqual(FileWeight.allocated(of: root.appendingPathComponent("box")),
                                    300_000)
    }

    /// A symlink is a few bytes of path text. Trashing one frees those bytes
    /// and not the tree at the other end — and the tree at the other end is
    /// still there afterwards, so charging it to the removal would be a promise
    /// of gigabytes the disk never gives back.
    func testASymlinkIsNotChargedTheWeightOfWhatItPointsAt() throws {
        try write("real/big.bin", bytes: 800_000)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(
            at: link, withDestinationURL: root.appendingPathComponent("real"))

        XCTAssertLessThan(FileWeight.allocated(of: link), 100_000,
                          "the symlink was charged the target's 800 KB")
    }

    // MARK: - Nothing there

    func testAPathThatIsNotThereWeighsNothingRatherThanCrashing() {
        XCTAssertEqual(FileWeight.allocated(of: root.appendingPathComponent("never-existed")), 0)
    }

    func testAnEmptyFileAndAnEmptyFolderAreZeroNotAnError() throws {
        try write("empty.bin", bytes: 0)
        let folder = root.appendingPathComponent("empty-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        XCTAssertEqual(FileWeight.allocated(of: root.appendingPathComponent("empty.bin")), 0)
        XCTAssertEqual(FileWeight.allocated(of: folder), 0)
    }

    /// A name with a path separator in it cannot exist, but the ones people do
    /// create — spaces, a leading dot, Cyrillic, an emoji, a tab — reach this
    /// through Leftovers and Autopilot, and a walk that loses one of them
    /// under-reports the removal.
    func testHostileNamesAreWalkedLikeAnyOther() throws {
        let names = ["two words.bin", ".dotfile.bin", "файл.bin", "🙂.bin", "tab\tname.bin"]
        for name in names { try write("hostile/\(name)", bytes: 100_000) }

        let total = FileWeight.allocated(of: root.appendingPathComponent("hostile"))
        XCTAssertGreaterThanOrEqual(total, 100_000 * names.count,
                                    "\(names.count) files of 100 KB weighed \(total)")
    }
}
