import XCTest
@testable import HelmRuntime

/// The gate and the move are two moments, and a symlinked ancestor can be
/// swapped between them.
///
/// Every removal gate resolves the symlinks in a path's parent chain at *check*
/// time (`RemovableScope.partition` → `PathCanonical.resolvingAncestors`);
/// `FileManager.trashItem` resolves them again at *act* time. Between the two,
/// the `FileWeight` walk that weighs the batch holds the door open for as long
/// as the batch is large — a width an attacker sets. Replace an approved
/// directory with a symlink to `~/Documents` inside that window and the gate's
/// approval of one subtree becomes a move of another.
///
/// `HelmTrash.remove` reads the resolved parent's identity once before the walk
/// and again immediately before the move, and refuses the path if it changed.
/// This does not *close* the window — the reference is taken as the batch
/// begins, not at the gate, and a swap that lands before that first read is not
/// caught, which is why the comment in `remove` is honest about narrowing to one
/// stat chain. It does take the walk, the wide part, out of the attacker's hands.
final class HelmTrashAncestrySwapTests: XCTestCase {

    private var root: URL!
    private var bin: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("helm-trash-ancestry-\(UUID().uuidString)")
        bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// The pure logic, no filesystem: the identity the batch reads changes
    /// between the reference read and the pre-move read, and the move is refused
    /// rather than attempted.
    func testAPathWhoseAncestryChangesBetweenGateAndMoveIsRefusedNotMoved() {
        var reads = 0
        var trashed: [String] = []

        let result = HelmTrash.remove(
            allowed: ["/Library/Caches/com.example/leftover.bin"],
            module: "test",
            ancestry: { _ in
                defer { reads += 1 }
                // Reference read first, pre-move read second — a different place.
                return PathCanonical.AncestryIdentity(device: 1, inode: reads == 0 ? 10 : 20)
            },
            trashing: { trashed.append($0.path) })

        XCTAssertEqual(result.removed, [], "a path whose ancestry moved was reported as removed")
        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan])
        XCTAssertEqual(result.refused.map(\.path), ["/Library/Caches/com.example/leftover.bin"])
        XCTAssertEqual(trashed, [], "the move was attempted on a path whose ancestor had been swapped")
        XCTAssertEqual(result.freedBytes, 0)
    }

    /// A path whose ancestry is steady is moved as before — the guard refuses a
    /// change, not everything.
    func testAPathWhoseAncestryHoldsStillIsMoved() {
        var trashed: [String] = []
        let result = HelmTrash.remove(
            allowed: ["/Library/Caches/com.example/leftover.bin"],
            module: "test",
            ancestry: { _ in PathCanonical.AncestryIdentity(device: 1, inode: 10) },
            trashing: { trashed.append($0.path) })

        XCTAssertEqual(result.refused, [])
        XCTAssertEqual(trashed, ["/Library/Caches/com.example/leftover.bin"])
    }

    /// The gate can approve a path whose parent does not exist yet — the scan
    /// resolves the deepest ancestor that does and re-appends the rest. If that
    /// parent is then *planted* (a symlink to a victim, created in the window),
    /// the reference is `nil` and the pre-move read is a real object: a change,
    /// and refused. Only a parent that stays absent is left to the missing-file
    /// branch.
    func testAParentPlantedWhereTheGateSawNoneIsRefused() {
        var reads = 0
        var trashed: [String] = []
        let result = HelmTrash.remove(
            allowed: ["/Library/Caches/com.example/not-there-yet/leftover.bin"],
            module: "test",
            ancestry: { _ in
                defer { reads += 1 }
                return reads == 0 ? nil : PathCanonical.AncestryIdentity(device: 1, inode: 99)
            },
            trashing: { trashed.append($0.path) })

        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan])
        XCTAssertEqual(trashed, [], "a parent planted after the gate let the move through")
    }

    /// End to end, with a real symlink swapped mid-batch. Two paths are handed
    /// over; trashing the first runs a closure that replaces the second's parent
    /// directory with a symlink pointing at a victim tree — exactly the swap the
    /// gate cannot see. The second must come back refused, its real bytes must
    /// still be on disk, and the victim behind the symlink must be untouched.
    func testASymlinkedAncestorSwappedDuringTheBatchRedirectsNothing() throws {
        let fm = FileManager.default

        // The approved subtree: `appdata/file.bin`, weighed and approved.
        let appdata = root.appendingPathComponent("appdata")
        try fm.createDirectory(at: appdata, withIntermediateDirectories: true)
        let approved = appdata.appendingPathComponent("file.bin")
        try Data(repeating: 0x41, count: 4_096).write(to: approved)

        // The trigger, trashed first (shorter path sorts first), whose move is
        // the attacker's moment.
        let trigger = root.appendingPathComponent("go.bin")
        try Data(repeating: 0x42, count: 16).write(to: trigger)

        // The victim: what the swapped symlink will point at.
        let evil = root.appendingPathComponent("evil")
        try fm.createDirectory(at: evil, withIntermediateDirectories: true)
        let victim = evil.appendingPathComponent("file.bin")
        try Data(repeating: 0x43, count: 4_096).write(to: victim)

        var trashed: [String] = []
        let result = HelmTrash.remove(
            allowed: [approved.path, trigger.path],
            module: "test",
            trashing: { url in
                if url.path == trigger.path {
                    // Swap `appdata` (a directory) for a symlink to `evil`, the
                    // way an attacker would between the weigh and the move.
                    try fm.moveItem(at: appdata,
                                    to: self.root.appendingPathComponent("appdata-real"))
                    try fm.createSymbolicLink(at: appdata, withDestinationURL: evil)
                }
                trashed.append(url.path)
                try fm.moveItem(at: url, to: self.bin.appendingPathComponent(url.lastPathComponent))
            })

        XCTAssertEqual(trashed, [trigger.path],
                       "the approved path was moved after its ancestor had been swapped")
        XCTAssertTrue(result.refused.contains { $0.path == approved.path },
                      "the redirected path was not refused")
        XCTAssertEqual(result.refused.first { $0.path == approved.path }?.reason,
                       .changedSinceScan)
        XCTAssertTrue(fm.fileExists(atPath: victim.path),
                      "the file behind the swapped symlink was trashed")
    }
}
