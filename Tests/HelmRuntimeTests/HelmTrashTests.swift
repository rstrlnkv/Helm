import XCTest
@testable import HelmRuntime

/// The trash loop, which four modules used to keep their own copy of — and
/// three of which threw the reason away.
final class HelmTrashTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = trashScratchDirectory("trash")
    }

    /// A file this test is going to trash for real, so its name is one nobody
    /// else could own and it is reclaimed by name afterwards — `TrashScratch`
    /// says why the parent directory's UUID does not do that job.
    private func file(_ name: String, bytes: Int = 16) throws -> String {
        let leaf = unownableLeaf(name)
        let url = root.appendingPathComponent(leaf)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        reclaimFromTrash(leaf)
        return url.path
    }

    func testItTrashesWhatItIsGivenAndTotalsTheBytes() throws {
        let one = try file("one.txt", bytes: 32)
        let two = try file("two.txt", bytes: 32)

        let result = HelmTrash.remove(allowed: [one, two], module: "test")

        XCTAssertEqual(Set(result.removed), [one, two])
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertGreaterThan(result.freedBytes, 0, "allocated size, not zero")
        XCTAssertFalse(FileManager.default.fileExists(atPath: one))
    }

    /// The gate's refusals arrive with the batch. Reporting them separately is
    /// how a count and a list end up disagreeing on the same screen.
    func testOutOfScopePathsComeBackAsRefusalsNotSilence() throws {
        let allowed = try file("ok.txt")
        let result = HelmTrash.remove(allowed: [allowed],
                                      outOfScope: ["/System/Library/CoreServices"],
                                      module: "test")

        XCTAssertEqual(result.removed, [allowed])
        XCTAssertEqual(result.refused,
                       [.init(path: "/System/Library/CoreServices", reason: .outOfScope)])
        XCTAssertEqual(result.failed, ["/System/Library/CoreServices"])
    }

    /// A path that is not there is a refusal with a reason, not a crash and not
    /// a silent success.
    func testAMissingPathIsRefusedWithAReason() {
        let ghost = root.appendingPathComponent("never-existed").path
        let result = HelmTrash.remove(allowed: [ghost], module: "test")

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.refused.count, 1)
        XCTAssertEqual(result.refused.first?.path, ghost)
        XCTAssertEqual(result.freedBytes, 0)
    }

    /// The one-line summary picks the reason that applies to most of the batch,
    /// so "3 items could not be moved" can say why without listing three.
    func testPrincipalReasonIsTheCommonestOne() {
        let result = HelmTrash.Result(
            removed: [],
            refused: [.init(path: "/a", reason: .outOfScope),
                      .init(path: "/b", reason: .needsFullDiskAccess),
                      .init(path: "/c", reason: .needsFullDiskAccess)],
            freedBytes: 0)
        XCTAssertEqual(result.principalReason, .needsFullDiskAccess)
    }

    func testPrincipalReasonIsNilWhenNothingRefused() {
        XCTAssertNil(HelmTrash.Result(removed: ["/a"], refused: [], freedBytes: 1).principalReason)
    }
}

/// What "freed" means when the thing trashed is a folder.
///
/// `HelmTrash` reads `totalFileAllocatedSize` on the path it is given. For a
/// file that is the file; for a directory it is the directory entry — a few
/// kilobytes, whatever is inside. Disk trashes folders for a living and
/// Leftovers trashes plug-in and extension bundles, so the figure both of them
/// show after a removal is the one number the screen exists to produce.
///
/// Leftovers never hit this because it kept its own loop and its own recursive
/// `size`. That is the difference that has to close before its loop can go.
final class HelmTrashFolderSizeTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = trashScratchDirectory("trash-size")
    }

    /// The item that will be trashed, named so the cleanup can find it in the
    /// Trash. Whatever is written *inside* it keeps its ordinary name — only
    /// the moved item's own name survives the move.
    private func trashable(_ name: String) -> (url: URL, path: String) {
        let leaf = unownableLeaf(name)
        let url = root.appendingPathComponent(leaf)
        reclaimFromTrash(leaf)
        return (url, url.path)
    }

    private func write(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func testAFolderFreesWhatIsInsideIt() throws {
        let bundle = trashable("bundle")
        try write(bundle.url.appendingPathComponent("Contents/payload.bin"), bytes: 400_000)
        try write(bundle.url.appendingPathComponent("Contents/Info.plist"), bytes: 2_000)

        let result = HelmTrash.remove(allowed: [bundle.path], module: "test")

        XCTAssertEqual(result.removed, [bundle.path])
        XCTAssertGreaterThan(result.freedBytes, 400_000,
                             "a folder reported the size of its directory entry, not its contents")
    }

    /// And a plain file still reports itself, not zero and not something else.
    func testAFileStillFreesItsOwnSize() throws {
        let file = trashable("one.bin")
        try write(file.url, bytes: 300_000)

        let result = HelmTrash.remove(allowed: [file.path], module: "test")

        XCTAssertEqual(result.removed, [file.path])
        XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000)
    }
}
