import XCTest
@testable import Module_Disk_Engine

/// The one number the Disk module exists to produce: how much a removal freed.
///
/// The scan and the removal measure the same folder with two different pieces
/// of code. `TreeBuilder` dedupes by file id — "a hard link's target is one
/// allocation however many names it has" — and the walk behind `HelmTrash`
/// counts names. So the ring can say a folder holds 400 KB and the banner
/// underneath can say removing it freed 800 KB, of the same folder, in the same
/// session, and only one of those is a thing a disk can do.
final class DiskTrashArithmeticTests: XCTestCase {

    private var root: URL!
    /// Unique, because the copy left behind is cleaned up out of the Trash by
    /// name — `trashItem` is called without `resultingItemURL`, so the name is
    /// all there is to go on, and it must not be a name anybody else could own.
    private var trashedName: String!

    override func setUpWithError() throws {
        trashedName = "helm-disk-freed-\(UUID().uuidString)"
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-disk-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        let fm = FileManager.default
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let trash = (try? fm.url(for: .trashDirectory, in: .userDomainMask,
                                 appropriateFor: home, create: false))
            ?? home.appendingPathComponent(".Trash")
        try? fm.removeItem(at: trash.appendingPathComponent(trashedName))
    }

    /// One 400 KB file with two names. Trashing the folder frees one
    /// allocation; the figure shown is the scan's own figure or it is wrong.
    func testAHardLinkedFileIsNotCountedTwiceInWhatWasFreed() async throws {
        let folder = root.appendingPathComponent(trashedName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("big.bin")
        try Data(repeating: 0x41, count: 400_000).write(to: file)
        try FileManager.default.linkItem(at: file,
                                         to: folder.appendingPathComponent("same.bin"))

        // What the app itself says this folder holds.
        let measured = try XCTUnwrap(DiskScanner().scan(root: folder.path)).bytes
        XCTAssertGreaterThan(measured, 0, "the scan has to have measured something")

        let removal = await DiskEngine().trash([folder.path])

        XCTAssertEqual(removal.removed, [folder.path])
        XCTAssertTrue(removal.refused.isEmpty, "\(removal.refused)")
        XCTAssertEqual(removal.freedBytes, measured,
                       "the removal and the scan disagree about the same folder")
    }
}

/// The folded bucket is a synthetic node the scan invents per directory, and it
/// is named `…`. `TreeBuilder.foldedBucket` finds it by `name == "…" && !isDirectory`
/// — which is also a description of a real file called `…`, a name a person can
/// type and Finder will accept.
///
/// The real file then becomes the bucket: every small file in that directory is
/// charged to it, the row on screen reports a size the file does not have, and
/// `UserFileScope` refuses anything ending in `/…`, so the one row whose size is
/// wrong is also the one row that cannot be put in the basket.
final class DiskFoldedBucketNameTests: XCTestCase {

    func testARealFileNamedLikeTheBucketStaysItsOwnEntry() {
        let builder = TreeBuilder(root: "/r", foldThreshold: 1_000)
        builder.addFile(path: "/r/…", bytes: 100_000, fileID: 1)
        builder.addFile(path: "/r/tiny.txt", bytes: 10, fileID: 2)

        let root = builder.build()

        XCTAssertEqual(root.bytes, 100_010, "precondition: both files were charged to the root")
        XCTAssertEqual(root.children.count, 2,
                       "the file the user has and the bucket the scan invented are two rows")
        // By the flag, not by the path: the bucket's path is the path a real file
        // called `…` would have, which is the whole reason `isFolded` exists.
        let real = root.children.first { !$0.isFolded }
        XCTAssertEqual(real?.bytes, 100_000, "the file's row shows the file's size")
    }
}
