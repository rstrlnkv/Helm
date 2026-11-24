import XCTest
import HelmRuntime
import HelmTestSupport
@testable import Module_Disk_Engine

/// The one number the Disk module exists to produce: how much a removal freed.
///
/// The scan and the removal measure the same folder with different code:
/// `TreeBuilder` counts a hard-linked file once, by file id, and the walk behind
/// `HelmTrash` counts names. The banner must not report more freed than the
/// ring showed the folder holding.
final class DiskTrashArithmeticTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = scratchDirectory("disk-root")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// One 400 KB file with two names. Trashing the folder frees one
    /// allocation; the figure shown is the scan's own figure or it is wrong.
    func testAHardLinkedFileIsNotCountedTwiceInWhatWasFreed() async throws {
        let folder = root.appendingPathComponent("helm-disk-freed")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("big.bin")
        try Data(repeating: 0x41, count: 400_000).write(to: file)
        try FileManager.default.linkItem(at: file,
                                         to: folder.appendingPathComponent("same.bin"))

        // What the app itself says this folder holds.
        let measured = try XCTUnwrap(DiskScanner().scan(root: folder.path)).bytes
        XCTAssertGreaterThan(measured, 0, "the scan has to have measured something")

        let removal = await DiskEngine(capacity: FakeCapacity(), trashing: { try FileManager.default.removeItem(at: $0) }).trash([folder.path])

        XCTAssertEqual(removal.removed, [folder.path])
        XCTAssertTrue(removal.refused.isEmpty, "\(removal.refused)")
        XCTAssertEqual(removal.freedBytes, measured,
                       "the removal and the scan disagree about the same folder")
    }
}

/// The engine's own gate: `DiskEngine.trash` partitions through `UserFileScope`
/// before `HelmTrash.remove`.
///
/// The path is a real file the gate refuses (`/usr/bin/true`), so an engine
/// without the gate would reach the move with it; a missing path would reach
/// the move too, and a fake that throws nothing would report it removed. The
/// move is a recording fake, so a run with the gate removed never touches the
/// real Trash.
final class DiskTrashGateTests: XCTestCase {

    func testAPathTheGateRefusesIsRefusedByTheEngineAndNotAttempted() async {
        let path = "/usr/bin/true"
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "precondition: the path exists")

        let attempted = Locked(0)

        let removal = await DiskEngine(capacity: FakeCapacity(), trashing: { _ in attempted.value = 1 }).trash([path])

        XCTAssertEqual(attempted.value, 0, "the engine handed a path outside the user's files to the move")
        XCTAssertTrue(removal.removed.isEmpty, "\(removal.removed)")
        XCTAssertEqual(removal.refused, [HelmTrash.Refusal(path: path, reason: .outOfScope)])
        XCTAssertEqual(removal.freedBytes, 0)
    }
}
