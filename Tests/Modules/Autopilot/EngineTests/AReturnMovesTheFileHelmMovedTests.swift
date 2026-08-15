import XCTest
import HelmRuntime
@testable import Module_Autopilot_Engine

/// Putting one action back, and the eight ways it must refuse instead.
///
/// A history record is data. It lives in the same plist the rules do — the one
/// any process running as this user can rewrite — so a record is not an
/// instruction, it is a *claim*, and every claim it makes is checked before
/// anything moves. The forged record below is the whole reason:
/// `{moved, destination: "~/Library/Messages/chat.db", path: "~/Downloads/x"}`
/// is a ready-made instruction to carry Full-Disk-Access content out to where
/// the forger can read it, written entirely in fields the section shows.
///
/// Every test here first asserts the thing it is about actually happened — a
/// refusal proves nothing if the file was never there to move.
final class AReturnMovesTheFileHelmMovedTests: XCTestCase {

    private let home = "/Users/x"
    private let key = Data(repeating: 0x11, count: 32)
    private var files: FakeUndoFiles!
    private var runner: UndoRunner!

    /// `~/Downloads/march.pdf` was moved to `~/Documents/Invoices/march.pdf`,
    /// and both ends are real.
    private let origin = "/Users/x/Downloads/march.pdf"
    private let landed = "/Users/x/Documents/Invoices/march.pdf"

    override func setUp() {
        files = FakeUndoFiles()
        files.makeDirectory("/Users/x/Downloads")
        files.makeDirectory("/Users/x/Documents/Invoices")
        files.put(landed, inode: 42)
        runner = UndoRunner(home: home, files: files)
    }

    private func record(_ kind: ActionRecord.Kind = .moved, at: String? = nil,
                        from: String? = nil, detail: String = "Invoices",
                        inode: UInt64? = 42, undoneAt: Date? = nil) -> ActionRecord {
        ActionRecord(at: Date(timeIntervalSince1970: 1), rule: "Invoices", file: "march.pdf",
                     kind: kind, detail: detail, path: from ?? origin,
                     destination: at ?? landed, run: "pass-1", ruleID: "rule-7",
                     device: inode.map { _ in 1 }, inode: inode, undoneAt: undoneAt)
    }

    // MARK: - The ordinary case

    func testAMovedFileGoesBackWhereItCameFrom() {
        XCTAssertNotNil(files.identity(of: landed), "nothing was moved, so this proves nothing")

        let outcome = runner.undo(record(), key: key)

        XCTAssertEqual(outcome, .restored(to: origin, stamped: true))
        XCTAssertEqual(files.moves.map(\.to), [origin])
        XCTAssertNil(files.identity(of: landed))
    }

    /// **The mark is written on the way back, not taken off.** A file put back
    /// unmarked is one the same rule takes again on the next sweep — the
    /// ping-pong this whole feature would otherwise create. Idempotent, so it
    /// covers every branch without one.
    func testTheReturnedFileIsMarkedForTheRuleThatActed() {
        _ = runner.undo(record(), key: key)
        XCTAssertEqual(files.stamps.map(\.path), [origin])
        XCTAssertEqual(files.stamps.map(\.rule), ["rule-7"], "marked for the wrong rule")
    }

    /// A volume that will not keep an extended attribute. The file is back —
    /// refusing the return over a mark would be the wrong end to fail at — and
    /// the outcome says the mark did not stick, so the report can offer to
    /// switch the rule off instead of letting it take the file again in an hour.
    func testAMarkThatWillNotStickIsReported() {
        files.stampSticks = false
        XCTAssertEqual(runner.undo(record(), key: key), .restored(to: origin, stamped: false))
        XCTAssertEqual(files.moves.count, 1, "the file was not put back at all")
    }

    // MARK: - The gate

    /// The forged record. `~/Library` is refused whole, so a record naming it
    /// is refused however plausible the rest of it looks.
    func testARecordNamingSomewhereNoRuleMayReachIsRefused() {
        let planted = "/Users/x/Library/Messages/chat.db"
        files.put(planted, inode: 42)
        files.makeDirectory("/Users/x/Library/Messages")
        XCTAssertNotNil(files.identity(of: planted), "the bait is not there")

        let outcome = runner.undo(record(at: planted, from: "/Users/x/Downloads/x.db"), key: key)

        XCTAssertEqual(outcome, .refused(.originOutOfScope))
        XCTAssertEqual(files.moves.count, 0, "Helm carried a protected file out of ~/Library")
    }

    /// And the other end: a record that would put the file *into* somewhere no
    /// rule may reach.
    func testARecordPointingBackIntoSomewhereNoRuleMayReachIsRefused() {
        files.makeDirectory("/Users/x/Library/LaunchAgents")
        let outcome = runner.undo(record(from: "/Users/x/Library/LaunchAgents/go.plist"), key: key)
        XCTAssertEqual(outcome, .refused(.originOutOfScope))
        XCTAssertEqual(files.moves.count, 0)
    }

    /// `~/.Trash` is inside home and outside `~/Library`, so the gate lets a
    /// return out of the Trash through. Pinned because a gate narrowed by
    /// somebody reading "never anywhere odd" would make the most valuable
    /// return of the four impossible.
    func testAReturnOutOfTheTrashIsNotRefusedByTheGate() {
        let bin = "/Users/x/.Trash/march 2.pdf"
        files.put(bin, inode: 42)
        XCTAssertEqual(runner.undo(record(.trashed, at: bin, detail: ""), key: key),
                       .restored(to: origin, stamped: true))
    }

    // MARK: - Is this still the file

    func testARecordWithNoIdentityIsRefusedRatherThanGuessed() {
        XCTAssertEqual(runner.undo(record(inode: nil), key: key), .refused(.noIdentity))
        XCTAssertEqual(files.moves.count, 0)
    }

    func testAFileThatIsNoLongerThereIsSaidSoRatherThanInvented() {
        files.remove(landed)
        XCTAssertEqual(runner.undo(record(), key: key), .refused(.notThere))
    }

    /// The Trash says it differently, and one phrasing covers both emptying it
    /// and taking the file out by hand: from here they are the same fact.
    func testAFileNoLongerInTheTrashSaysTheTrashWasEmptied() {
        let bin = "/Users/x/.Trash/march.pdf"
        XCTAssertNil(files.identity(of: bin))
        XCTAssertEqual(runner.undo(record(.trashed, at: bin, detail: ""), key: key),
                       .refused(.trashEmptied))
    }

    /// Something else is standing at that path now. Without this the return
    /// moves whatever arrived after, which is a file Helm never touched.
    func testAFileSwappedForAnotherIsNotMoved() {
        files.put(landed, inode: 99)
        XCTAssertNotNil(files.identity(of: landed), "nothing is there, so this proves nothing")
        XCTAssertEqual(runner.undo(record(), key: key), .refused(.notTheSameFile))
        XCTAssertEqual(files.moves.count, 0)
    }

    func testARecordAlreadyPutBackIsNotPutBackAgain() {
        XCTAssertEqual(runner.undo(record(undoneAt: Date(timeIntervalSince1970: 2)), key: key),
                       .refused(.alreadyUndone))
        XCTAssertEqual(files.moves.count, 0)
    }

    // MARK: - Where it came from

    /// The folder is not created. A rule that emptied `~/Downloads/2025` into a
    /// bucket, and a person who has since deleted `2025`, are asking for the
    /// file back — not for the folder back — and inventing the folder is the
    /// return deciding something nobody asked it to.
    func testAFolderThatIsGoneIsNotRecreated() {
        let gone = "/Users/x/Downloads/2025/march.pdf"
        XCTAssertFalse(files.directoryExists("/Users/x/Downloads/2025"))
        XCTAssertEqual(runner.undo(record(from: gone), key: key), .refused(.originGone))
        XCTAssertEqual(files.moves.count, 0)
    }

    /// A move numbers, the way the Finder numbers a copy and the way the rule
    /// itself did on the way out — and the outcome names what it settled on, so
    /// the report can say the file is back under another name.
    func testAMoveWhoseOldNameIsTakenIsNumberedAndSaysSo() {
        files.put(origin, inode: 7)
        XCTAssertEqual(runner.undo(record(), key: key),
                       .restored(to: "/Users/x/Downloads/march 2.pdf", stamped: true))
        XCTAssertNotNil(files.identity(of: origin), "the file that was already there was overwritten")
    }

    /// A rename must not. The subject of the operation *is* the name, so
    /// numbering would put the file back under a name nobody ever gave it —
    /// which is not what was undone.
    func testARenameWhoseOldNameIsTakenRefuses() {
        let before = "/Users/x/Downloads/scan.pdf"
        let after = "/Users/x/Downloads/Invoice 2025.pdf"
        files.put(after, inode: 42)
        files.put(before, inode: 7)
        XCTAssertEqual(runner.undo(record(.renamed, at: after, from: before,
                                          detail: "Invoice 2025.pdf"), key: key),
                       .refused(.nameTaken))
        XCTAssertEqual(files.moves.count, 0)
    }

    // MARK: - The window between the check and the move

    /// The same seam the runner's own act takes: where a path leads is read at
    /// the gate and again beside the move, and a directory swapped for a link
    /// in between is refused rather than followed.
    func testAnAncestorSwappedAfterTheCheckStopsTheReturn() {
        files.swapAncestry(of: origin, after: 1, to: 12_345)
        XCTAssertEqual(runner.undo(record(), key: key), .refused(.changedSinceCheck))
        XCTAssertEqual(files.moves.count, 0)
    }

    /// And the end the file is coming *from*, which the same swap reaches.
    func testTheSourceLeadingSomewhereElseStopsTheReturn() {
        files.swapAncestry(of: landed, after: 1, to: 54_321)
        XCTAssertEqual(runner.undo(record(), key: key), .refused(.changedSinceCheck))
        XCTAssertEqual(files.moves.count, 0)
    }

    // MARK: - Tags

    func testATagIsTakenOffAgain() {
        files.tag(landed, ["Holiday", "Paid"])
        let outcome = runner.undo(record(.tagged, at: landed, from: landed, detail: "Paid"),
                                  key: key)
        XCTAssertEqual(outcome, .restored(to: landed, stamped: true))
        XCTAssertEqual(files.tags(at: landed), ["Holiday"], "the person's own tag went with it")
        XCTAssertEqual(files.moves.count, 0, "a tag was undone by moving the file")
    }

    /// The tag is not there any more, so there is nothing to take off — said
    /// plainly rather than reported as a success that did nothing.
    func testATagAlreadyGoneSaysSo() {
        files.tag(landed, ["Holiday"])
        XCTAssertEqual(runner.undo(record(.tagged, at: landed, from: landed, detail: "Paid"),
                                   key: key),
                       .refused(.alreadyUndone))
    }

    // MARK: - When the move itself fails

    func testAMoveThatFailsIsReportedRatherThanCountedAsDone() {
        files.moveFails = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        guard case .failed = runner.undo(record(), key: key) else {
            return XCTFail("a move that could not happen was reported as a return")
        }
    }

    /// No key is no marks — the same state `RuleRunner` is handed when the
    /// keychain will not answer. The file still goes back; what it cannot be is
    /// marked, and the outcome says so.
    func testWithNoKeyTheFileGoesBackUnmarked() {
        XCTAssertEqual(runner.undo(record(), key: nil), .restored(to: origin, stamped: false))
        XCTAssertEqual(files.stamps.count, 0)
    }
}
