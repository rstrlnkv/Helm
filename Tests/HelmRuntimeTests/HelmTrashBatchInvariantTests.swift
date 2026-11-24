import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `HelmTrash.remove` is where every module goes to delete, and its result is
/// read two ways at once: `removed` is counted for "N moved to
/// Trash", `refused`/`failed` is listed for "these did not go". Those two lists
/// describe the same batch, so nothing may appear in both — a path in both is a
/// screen that says one file went and the same file did not.
///
/// `NSFileNoSuchFileError` counts as a success when the path went with a
/// parent taken earlier in the same batch, which is string matching over
/// `allowed`, and `allowed` is whatever the caller passed.
final class HelmTrashBatchInvariantTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("trash-batch")
    }

    /// A file this batch will really trash, reclaimed from the Trash and not
    /// from its source, which the move has emptied (`TrashScratch`).
    @discardableResult
    /// Not the shared `write` on its own: this file is going to the Trash, so
    /// its leaf has to be a name nobody else could own and the reclamation has
    /// to be registered before the move rather than after it.
    private func trashableFile(_ name: String, bytes: Int = 4_096) throws -> String {
        let leaf = unownableLeaf(name)
        reclaimFromTrash(leaf)
        return try write(leaf, in: root, bytes: bytes).path
    }

    /// A folder with one file in it. The **folder** is what goes to the Trash,
    /// so it is the folder's name that has to be unownable; the child travels
    /// inside it and keeps its own.
    private func folderWithChild(_ name: String, child: String, bytes: Int = 4_096)
    throws -> (folder: String, child: String) {
        let leaf = unownableLeaf(name)
        let directory = root.appendingPathComponent(leaf)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(child)
        try Data(repeating: 0x41, count: bytes).write(to: file)
        reclaimFromTrash(leaf)
        return (directory.path, file.path)
    }

    /// The duplicated input. A basket assembled from two screens, or a list a
    /// caller forgot to put through a `Set`, hands the same path twice. It is
    /// one file and one outcome, whichever way it goes.
    func testAPathGivenTwiceHasOneOutcome() throws {
        let file = try trashableFile("one.bin")

        let result = HelmTrash.remove(allowed: [file, file], module: "test")

        XCTAssertTrue(Set(result.removed).isDisjoint(with: Set(result.failed)),
                      "the same path was reported both moved and refused: "
                      + "removed \(result.removed), refused \(result.failed)")
    }

    /// And the count that goes on the banner has to match. Three names, two
    /// files: the person is told about three things when two moved.
    func testTheTotalsDescribeTheBatchAndNotTheSpelling() throws {
        let one = try trashableFile("one.bin")
        let two = try trashableFile("two.bin")

        let result = HelmTrash.remove(allowed: [one, two, one], module: "test")

        XCTAssertEqual(result.removed.count + result.refused.count, 2,
                       "two files were in the batch; the result accounts for "
                       + "\(result.removed.count) moved and \(result.refused.count) refused")
    }

    /// The other spelling of one path. The length sort and the
    /// `hasPrefix($0 + "/")` parent check read the exact characters, while a
    /// trailing slash names the same directory to every filesystem call. Read
    /// wrong, the child is "already gone before any of this started", a
    /// refusal, and somebody is sent looking for a file that is in the Trash.
    func testAFolderWithATrailingSlashStillTakesItsChildrenWithIt() throws {
        let (folder, child) = try folderWithChild("folder", child: "inside.bin")

        let result = HelmTrash.remove(allowed: [folder + "/", child], module: "test")

        XCTAssertTrue(result.refused.isEmpty,
                      "the child went with its parent in this very batch, and was reported "
                      + "as \(result.refused.map(\.reason))")
    }
}

/// What `FileWeight` says a path is worth, for the paths that are not simply a
/// file or a folder.
///
/// The figure it returns is the one shown as "Freed N" after a removal and the
/// one Autopilot's size conditions are matched against, so it has to mean
/// "what deleting this gives back" — its own doc comment's words.
final class FileWeightIndirectionTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("weight")
    }

    /// A symlink is a few dozen bytes and deleting it frees a few dozen bytes.
    /// `isDirectory` is answered about what the link points at, so a walk
    /// entered on it would report the target: Disk's banner would claim the
    /// target freed, and an Autopilot "larger than 100 MB" rule would match a
    /// 60-byte link.
    func testASymlinkWeighsWhatDeletingItGivesBack() throws {
        let target = root.appendingPathComponent("big")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2_000_000)
            .write(to: target.appendingPathComponent("payload.bin"))
        let link = root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertLessThan(FileWeight.allocated(of: link), 1_000_000,
                          "a symlink reported the weight of its target: "
                          + "\(FileWeight.allocated(of: link)) bytes for a link")
    }
}
