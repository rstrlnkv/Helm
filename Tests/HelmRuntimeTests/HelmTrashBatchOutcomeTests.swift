import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// A batch that contains a folder and something inside it, in either order,
/// asserted absolutely.
///
/// Disk reaches this without trying: the advice list offers `~/Library/Caches`
/// while the ring, three levels down, offers `~/Library/Caches/com.acme.tool`,
/// and `toggleBasket` only dedupes by exact path. Both go into one basket and
/// one `trash` call.
///
/// Whichever goes first, both are gone afterwards. If the parent went first,
/// the child's own `trashItem` fails with `NSFileNoSuchFileError`, which must
/// not reach the screen as macOS refusing a file already in the Trash. The
/// order is a hash seed's (`DiskEngine.trash` feeds `Array(Set(paths))`).
///
/// Comparing the two orders proves nothing, since `remove` sorts the batch
/// first, so the assertion is absolute: both paths gone, no refusal, the bytes
/// counted once.
final class HelmTrashBatchOutcomeTests: XCTestCase {

    /// A folder holding one 300 KB file. Returns (parent, child).
    private func makeTree() throws -> (String, String) {
        let root = scratchDirectory("batch")
        let name = unownableLeaf("helm-batch-folder")
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let childName = unownableLeaf("helm-batch-file.bin")
        try Data(repeating: 0x41, count: 300_000)
            .write(to: folder.appendingPathComponent(childName))
        reclaimFromTrash(name)
        reclaimFromTrash(childName)
        return (folder.path, folder.appendingPathComponent(childName).path)
    }

    func testEitherOrderRemovesBothPathsRefusesNothingAndCountsTheBytesOnce() throws {
        for parentFirst in [true, false] {
            let (parent, child) = try makeTree()
            let batch = parentFirst ? [parent, child] : [child, parent]

            let result = HelmTrash.remove(allowed: batch, module: "test")
            let order = parentFirst ? "parent first" : "child first"

            XCTAssertEqual(Set(result.removed), [parent, child],
                           "\(order): the batch reports \(result.removed.count) of 2 removed")
            XCTAssertEqual(result.refused, [],
                           "\(order): a path this batch took is not something the person "
                           + "can act on — \(result.refused)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: parent), "\(order)")
            XCTAssertGreaterThanOrEqual(result.freedBytes, 300_000, "\(order)")
            XCTAssertLessThan(result.freedBytes, 600_000,
                              "\(order): the 300 KB inside the folder was counted twice — "
                              + "once for the folder and once for the file basketed with it")
        }
    }

    /// The other half of the rule: a path that was already gone before the batch
    /// started stays a refusal. The list on screen is minutes old, and "it was
    /// not there" is the one thing worth telling the person about it.
    func testAPathGoneBeforeTheBatchIsStillARefusalEvenBesideARemovedFolder() throws {
        let (parent, _) = try makeTree()
        // Not under `parent`: a sibling that vanished between the scan and now.
        let vanished = URL(fileURLWithPath: parent).deletingLastPathComponent()
            .appendingPathComponent("never-existed.bin").path

        let result = HelmTrash.remove(allowed: [parent, vanished], module: "test")

        XCTAssertEqual(result.removed, [parent])
        XCTAssertEqual(result.refused.map(\.path), [vanished],
                       "a stale row was reported as though the batch had taken it")
    }
}
