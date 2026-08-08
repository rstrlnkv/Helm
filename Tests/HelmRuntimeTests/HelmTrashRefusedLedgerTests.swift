import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// What a refused path does to the batch's hard-link ledger.
///
/// `counted` is one `Set` of file ids for the whole batch, so an allocation
/// wearing several names is charged to `freedBytes` once — the rule the ring
/// and the banner disagreed about before `FileWeight` took it. The weighing
/// happens *before* the ancestry recheck, and it has to: the recheck is the
/// last thing before the move, which is the whole point of it. So a path that
/// is then refused has already written its file ids into the ledger, and a
/// second name for the same allocation, later in the same batch, is weighed as
/// something already counted and adds nothing.
///
/// The batch is left saying it freed nothing while a file it really did trash
/// is sitting in the Trash — and the number is what the banner shows.
final class HelmTrashRefusedLedgerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = trashScratchDirectory("trash-ledger")
    }

    /// Two names for one allocation: the first is refused mid-batch, the second
    /// is trashed. `a` is the shorter path, so the batch reaches it first.
    private func twoNamesForOneFile(bytes: Int) throws -> (refused: String, trashed: String) {
        let first = root.appendingPathComponent(unownableLeaf("a.bin"))
        let second = root.appendingPathComponent(unownableLeaf("bb.bin"))
        try Data(repeating: 0x41, count: bytes).write(to: first)
        XCTAssertEqual(link(first.path, second.path), 0, "the hard link could not be made")
        reclaimFromTrash(second.lastPathComponent)
        return (first.path, second.path)
    }

    /// The ancestry recheck's refusal. It must give the ledger back.
    func testAPathRefusedForItsAncestryDoesNotSpendTheBatchesLedger() throws {
        let names = try twoNamesForOneFile(bytes: 400_000)
        // Each path is read twice: once for the batch's reference, once
        // immediately before its move. Only the first name's second read moves.
        var reads: [String: Int] = [:]

        let result = HelmTrash.remove(
            allowed: [names.refused, names.trashed],
            module: "test",
            ancestry: { path in
                let seen = reads[path, default: 0]
                reads[path] = seen + 1
                let swapped = path == names.refused && seen > 0
                return PathCanonical.AncestryIdentity(device: 1, inode: swapped ? 20 : 10)
            },
            trashing: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) })

        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan],
                       "precondition: the first name was refused")
        XCTAssertEqual(result.removed, [names.trashed],
                       "precondition: the second name really did go to the Trash")
        XCTAssertGreaterThanOrEqual(result.freedBytes, 400_000,
                                    "the refused path spent the allocation the trashed one freed")
    }

    /// The same for a move macOS refuses: nothing left the disk, so nothing
    /// was charged, and the next name for that allocation is still the batch's
    /// to weigh.
    func testAPathMacOSRefusesDoesNotSpendTheBatchesLedger() throws {
        let names = try twoNamesForOneFile(bytes: 400_000)

        let result = HelmTrash.remove(
            allowed: [names.refused, names.trashed],
            module: "test",
            trashing: { url in
                if url.path == names.refused {
                    throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
                }
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            })

        XCTAssertEqual(result.removed, [names.trashed], "precondition")
        XCTAssertGreaterThanOrEqual(result.freedBytes, 400_000,
                                    "a move that failed spent the allocation the next name freed")
    }

    /// The control, and the rule this must not undo: two names for one
    /// allocation that **both** go to the Trash are still charged once.
    func testTwoNamesThatBothGoAreStillWeighedOnce() throws {
        let names = try twoNamesForOneFile(bytes: 400_000)
        reclaimFromTrash(URL(fileURLWithPath: names.refused).lastPathComponent)

        let result = HelmTrash.remove(allowed: [names.refused, names.trashed], module: "test")

        XCTAssertEqual(Set(result.removed), Set([names.refused, names.trashed]), "precondition")
        XCTAssertLessThan(result.freedBytes, 800_000,
                          "one allocation was counted twice, once per name")
    }
}
