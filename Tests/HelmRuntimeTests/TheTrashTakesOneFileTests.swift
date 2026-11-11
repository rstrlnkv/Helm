import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The one-file entry: a path that has passed its caller's gate, its answer a
/// sum, and the Trash it moves into a scratch folder of the test's own.
///
/// **Never `moveToTrashSayingWhere` here.** Every closure below moves into a bin
/// inside the scratch tree or throws; nothing reaches anybody's Trash.
final class TheTrashTakesOneFileTests: XCTestCase {

    private var root: URL!
    private var bin: URL!
    private var file: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("trash-one-file")
        bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        file = root.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: file)
    }

    /// Moves for real, into the bin, under a name that is not the file's own —
    /// the way the Trash renames a collision — and says where.
    private func landing(_ url: URL) throws -> URL? {
        let landed = bin.appendingPathComponent("a 2.pdf")
        try FileManager.default.moveItem(at: url, to: landed)
        return landed
    }

    private func reading(_ path: String) -> PathCanonical.AncestryIdentity? {
        PathCanonical.ancestryIdentity(of: path)
    }

    func testTheLandedURLIsReturned() {
        let answer = HelmTrash.removeOne(file.path, approved: reading(file.path),
                                         ancestry: reading, trashing: landing)
        XCTAssertEqual(answer, .trashed(at: bin.appendingPathComponent("a 2.pdf")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: bin.appendingPathComponent("a 2.pdf").path))
    }

    func testAMoveThatWillNotSayWhereIsStillTrashed() {
        var calls = 0
        let answer = HelmTrash.removeOne(file.path, approved: reading(file.path), ancestry: reading) { url in
            calls += 1
            try FileManager.default.removeItem(at: url)
            return nil
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(answer, .trashed(at: nil))
    }

    /// The recheck stops the move: the closure is never called. The control sits
    /// beside it — a matching reading does call it.
    func testAChangedAncestryStopsTheMoveBeforeItStarts() throws {
        let other = scratchDirectory("trash-one-file-other")
        var calls = 0
        let answer = HelmTrash.removeOne(file.path, approved: reading(other.path),
                                         ancestry: reading) { _ in calls += 1; return nil }
        XCTAssertEqual(calls, 0, "the move ran after the ancestry changed")
        XCTAssertEqual(answer, .refused(HelmTrash.Refusal(path: file.path, reason: .changedSinceScan),
                                        said: nil))

        _ = HelmTrash.removeOne(file.path, approved: reading(file.path),
                                ancestry: reading) { _ in calls += 1; return nil }
        XCTAssertEqual(calls, 1, "the control: a matching reading must reach the move")
    }

    /// Strict, unlike a batch: no earlier turn can have taken the parent.
    func testAParentThatIsGoneIsAChange() throws {
        let folder = root.appendingPathComponent("gone")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let inside = folder.appendingPathComponent("b.pdf")
        let approved = reading(inside.path)
        XCTAssertNotNil(approved)
        try FileManager.default.removeItem(at: folder)
        var calls = 0
        let answer = HelmTrash.removeOne(inside.path, approved: approved,
                                         ancestry: reading) { _ in calls += 1; return nil }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(answer, .refused(HelmTrash.Refusal(path: inside.path, reason: .changedSinceScan),
                                        said: nil))
    }

    func testEachErrorCodeGivesItsReasonAndTheSystemsSentence() {
        let cases: [(Int, TrashFailure.Reason)] = [
            (NSFileNoSuchFileError, .missing),
            (NSFileWriteNoPermissionError, .noPermission),
            (NSFileWriteVolumeReadOnlyError, .readOnlyVolume),
            (NSFileWriteOutOfSpaceError, .diskFull),
        ]
        for (code, reason) in cases {
            let error = NSError(domain: NSCocoaErrorDomain, code: code)
            let answer = HelmTrash.removeOne(file.path, approved: reading(file.path),
                                             ancestry: reading) { _ in throw error }
            XCTAssertEqual(answer, .refused(HelmTrash.Refusal(path: file.path, reason: reason),
                                            said: HelmFailure.describe(error)), "code \(code)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "a refused file moved")
    }

    /// A path is in exactly one arm, whatever the closure does.
    func testThePathIsAlwaysInExactlyOneArm() {
        let closures: [(URL) throws -> URL?] = [
            landing, { _ in nil },
            { _ in throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) },
        ]
        for closure in closures {
            let fresh = root.appendingPathComponent("fresh-\(UUID().uuidString).pdf")
            try? Data("y".utf8).write(to: fresh)
            switch HelmTrash.removeOne(fresh.path, approved: reading(fresh.path),
                                       ancestry: reading, trashing: closure) {
            case .trashed: break
            case let .refused(refusal, _): XCTAssertEqual(refusal.path, fresh.path)
            }
        }
    }
}
