import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A move that answers success and leaves the item is not a removal.
///
/// `trashing` returning is all `remove` used to ask; a sealed or
/// system-protected place can return and leave the file, and the batch then
/// counted the path and its bytes. The item itself is what is asked after, so
/// a symlink left in place is still there when its target is gone.
final class HelmTrashSealedTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = trashScratchDirectory("trash-sealed")
    }

    private func file(_ base: String, bytes: Int = 300_000) throws -> String {
        let url = root.appendingPathComponent(unownableLeaf(base))
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url.path
    }

    func testAMoveThatReturnsAndLeavesTheFileIsRefusedAndNotCounted() throws {
        let stays = try file("stays.bin")
        let goes = try file("goes-longer.bin")
        reclaimFromTrash(URL(fileURLWithPath: goes).lastPathComponent)

        let result = HelmTrash.remove(allowed: [stays, goes], module: "test",
                                      trashing: { url in
            if url.path == goes { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        })

        XCTAssertEqual(result.removed, [goes])
        XCTAssertEqual(result.refused, [HelmTrash.Refusal(path: stays, reason: .systemRefused)])
        XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000)
        XCTAssertLessThan(result.freedBytes, 600_000, "the left file's bytes were counted")
    }

    func testAloneItFreesNothing() throws {
        let stays = try file("alone.bin")
        let result = HelmTrash.remove(allowed: [stays], module: "test", trashing: { _ in })
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.failed, [stays])
        XCTAssertEqual(result.freedBytes, 0)
    }

    func testASymlinkLeftInPlaceIsRefusedEvenWhenItsTargetIsGone() throws {
        let target = try file("target.bin")
        let link = root.appendingPathComponent(unownableLeaf("link.bin")).path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        try FileManager.default.removeItem(atPath: target)
        XCTAssertFalse(FileManager.default.fileExists(atPath: link), "precondition: dangling")

        let result = HelmTrash.remove(allowed: [link], module: "test", trashing: { _ in })

        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.refused, [HelmTrash.Refusal(path: link, reason: .systemRefused)])
    }

    /// The control: another file under the name after a real move is not the
    /// item that was asked to go (a caller may put its replacement there).
    func testADifferentFileUnderTheNameAfterTheMoveIsNotTheOneLeftBehind() throws {
        let gone = try file("replaced.bin")
        reclaimFromTrash(URL(fileURLWithPath: gone).lastPathComponent)

        let result = HelmTrash.remove(allowed: [gone], module: "test", trashing: { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            try Data("squatter".utf8).write(to: url)
        })

        XCTAssertEqual(result.removed, [gone])
        XCTAssertEqual(result.refused, [])
    }

    // MARK: - removeOne goes through the same check

    private func approved(_ path: String) -> PathCanonical.AncestryIdentity? {
        PathCanonical.ancestryIdentity(of: path)
    }

    func testRemoveOneRefusesAMoveThatReturnsAndLeavesTheFile() throws {
        let stays = try file("one-stays.bin")
        let answer = HelmTrash.removeOne(stays, approved: approved(stays),
                                         ancestry: { self.approved($0) }, trashing: { _ in nil })
        guard case let .refused(refusal, _) = answer else { return XCTFail("\(answer)") }
        XCTAssertEqual(refusal, HelmTrash.Refusal(path: stays, reason: .systemRefused))
    }

    func testRemoveOneStillTrashesAFileThatLeaves() throws {
        let goes = try file("one-goes.bin")
        let answer = HelmTrash.removeOne(goes, approved: approved(goes), ancestry: { self.approved($0) },
                                         trashing: { try FileManager.default.removeItem(at: $0); return nil })
        XCTAssertEqual(answer, .trashed(at: nil))
    }

    // MARK: - unreadable is not absent

    /// A parent with no search permission makes `lstat` answer EACCES, not ENOENT.
    /// The mover must not run, and nothing is charged.
    func testAPathThatCannotBeReadBeforeTheMoveIsRefusedAndNotAttempted() throws {
        let parent = root.appendingPathComponent(unownableLeaf("sealed-parent"))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let inside = parent.appendingPathComponent("inside.bin")
        try Data(repeating: 0x41, count: 300_000).write(to: inside)
        XCTAssertEqual(chmod(parent.path, 0o000), 0)
        addTeardownBlock { chmod(parent.path, 0o755) }
        XCTAssertEqual(access(inside.path, F_OK), -1, "precondition: not readable")
        var attempted = false

        let result = HelmTrash.remove(allowed: [inside.path], module: "test",
                                      ancestry: { _ in nil }, trashing: { _ in attempted = true })
        XCTAssertFalse(attempted, "a path that could not be read was moved")
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.refused, [HelmTrash.Refusal(path: inside.path, reason: .unreadable)])
        XCTAssertEqual(result.freedBytes, 0)

        let one = HelmTrash.removeOne(inside.path, approved: nil, ancestry: { _ in nil },
                                      trashing: { _ in attempted = true; return nil })
        XCTAssertFalse(attempted)
        guard case let .refused(refusal, _) = one else { return XCTFail("\(one)") }
        XCTAssertEqual(refusal.reason, .unreadable)
    }

    /// Readable before the move, unreadable after it: the mover returns and the
    /// parent has been sealed, so «still there» cannot be told from «gone». Not
    /// believed, not charged.
    func testAPathThatCannotBeReadAfterTheMoveIsRefusedAndNotCounted() throws {
        let parent = root.appendingPathComponent(unownableLeaf("sealed-after"))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        let inside = parent.appendingPathComponent("inside.bin")
        try Data(repeating: 0x41, count: 300_000).write(to: inside)
        addTeardownBlock { chmod(parent.path, 0o755) }
        XCTAssertEqual(access(inside.path, F_OK), 0, "precondition: readable before the move")
        var moved = false

        let result = HelmTrash.remove(allowed: [inside.path], module: "test",
                                      ancestry: { _ in nil }, trashing: { _ in
            moved = true
            XCTAssertEqual(chmod(parent.path, 0o000), 0)
        })
        XCTAssertTrue(moved, "the mover never ran")
        XCTAssertEqual(access(inside.path, F_OK), -1, "precondition: unreadable after the move")
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.refused, [HelmTrash.Refusal(path: inside.path, reason: .unreadable)])
        XCTAssertEqual(result.freedBytes, 0)
    }
}
