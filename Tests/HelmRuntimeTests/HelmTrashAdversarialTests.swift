import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// The shared trash loop meeting the batches a real screen can assemble.
///
/// `HelmTrashTests` covers the loop's ordinary day. This is the rest: two
/// spellings of one path in one basket, a port that reports something the disk
/// contradicts, a symlink, a name with a tab in it, and a path that merely
/// *looks* like a child of another.
///
/// **Nothing here reaches anybody's Trash.** `remove` takes the move as a
/// parameter, so these hand it a closure that really moves the item — into a
/// bin inside the test's own temporary tree. A closure that recorded the path
/// and left the file alone would make half this file unwritable: a folder and
/// something inside it would both "succeed", and the rules that exist for that
/// case could not fail whatever anybody asserted.
final class HelmTrashAdversarialTests: XCTestCase {

    private var root: URL!
    private var bin: URL!
    private var moved: [String] = []

    override func setUpWithError() throws {
        root = scratchDirectory("trash-adversarial")
        bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        moved = []
    }

    /// A move that really moves, the way `FileManager.trashItem` does, and
    /// answers `NSFileNoSuchFileError` for something that is not there.
    private func moving(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path)
                || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        try FileManager.default.moveItem(
            at: url,
            to: bin.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)"))
        moved.append(url.path)
    }

    private func remove(_ allowed: [String],
                        outOfScope: [String] = [],
                        trashing: ((URL) throws -> Void)? = nil) -> HelmTrash.Result {
        HelmTrash.remove(allowed: allowed, outOfScope: outOfScope, module: "test",
                         trashing: trashing ?? { try self.moving($0) })
    }

    // MARK: - A port that contradicts the disk

    /// **A port may lie, and the loop reads its answer against the disk.** The
    /// "it went with its parent" branch forgives an `NSFileNoSuchFileError` —
    /// but only when the file really is gone *and* this batch is what took its
    /// parent. A port that reports the file missing while it is still sitting
    /// there (an XPC helper answering for a volume that has since remounted,
    /// a stubbed port in the wrong state) must not have that forgiveness: the
    /// file is on the disk, and telling the person it moved is the one answer
    /// they cannot check.
    func testAPortThatCallsAFileMissingWhileItIsStillThereIsRefusedNotForgiven() throws {
        let parent = try write("Ghost/inside/child.bin", in: root, bytes: 40_000).path
        let folder = root.appendingPathComponent("Ghost").path

        let result = remove([folder, parent]) { _ in
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }

        XCTAssertEqual(result.removed, [],
                       "the port moved nothing, so nothing may be reported as moved")
        XCTAssertEqual(Set(result.refused.map(\.path)), [folder, parent])
        XCTAssertEqual(Set(result.refused.map(\.reason)), [.missing])
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent),
                      "the file is gone, so the refusal above was the honest answer and "
                      + "this test is about a different program")
    }

    // MARK: - Two spellings of one path

    /// A trailing separator names the same folder and is a different string.
    /// One basket assembled from two screens can hold both — a scan that took
    /// its root from a stored path and a row built from a `URL` — and the batch
    /// has to answer once for the folder, not once per spelling.
    func testAFolderSpelledWithAndWithoutItsTrailingSeparatorIsOneOutcome() throws {
        try write("Ghost/inside.bin", in: root, bytes: 60_000)
        let folder = root.appendingPathComponent("Ghost").path

        let result = remove([folder, folder + "/"])

        XCTAssertEqual(result.removed.count + result.refused.count, 1,
                       "one folder produced \(result.removed.count) removals and "
                       + "\(result.refused.count) refusals: \(result.removed) \(result.refused)")
        XCTAssertEqual(result.removed, [folder])
        XCTAssertEqual(moved, [folder], "the move was attempted twice for one folder")
        XCTAssertGreaterThanOrEqual(result.freedBytes, 60_000)
        XCTAssertLessThan(result.freedBytes, 120_000, "the folder was counted once per spelling")
    }

    /// The normalisation used to strip **one** trailing separator, and a path
    /// joined onto a root that already ended in one has two. `…/Ghost` and
    /// `…/Ghost//` then survived the dedupe as two different strings; the first
    /// was moved, the second met `NSFileNoSuchFileError`, and the "went with its
    /// parent" branch fired — because `"…/Ghost/".hasPrefix("…/Ghost" + "/")` is
    /// true. One folder came back as two removals, and `removed.count` is what
    /// the banner counts.
    ///
    /// The stated rule is "one outcome per path, whatever the caller handed
    /// over", and it is stated because `removed` and `failed` are read as one
    /// description of one batch.
    func testAPathCarryingADoubledSeparatorIsStillOneOutcome() throws {
        try write("Ghost/inside.bin", in: root, bytes: 60_000)
        let folder = root.appendingPathComponent("Ghost").path

        let result = remove([folder, folder + "//"])

        XCTAssertEqual(moved, [folder], "the move was attempted more than once")
        XCTAssertEqual(result.removed.count + result.refused.count, 1,
                       "one folder came back as \(result.removed.count) removals and "
                       + "\(result.refused.count) refusals: \(result.removed)")
    }

    // MARK: - Looks like a child, is not one

    /// The ancestry test is a raw prefix comparison, and `…/Ghost` is a prefix
    /// of `…/Ghostly.bin`. The separator is what makes it an ancestry test
    /// rather than a spelling coincidence — without it, a stale row whose name
    /// merely starts with a folder's name would be reported as moved when it
    /// was never there at all.
    ///
    /// The folder is asserted removed first, so the refusal below is a refusal
    /// and not the whole batch failing.
    func testAPathThatMerelyStartsWithAnotherIsNotForgivenAsItsChild() throws {
        try write("Ghost/inside.bin", in: root, bytes: 20_000)
        let folder = root.appendingPathComponent("Ghost").path
        let lookalike = root.appendingPathComponent("Ghostly.bin").path   // never existed

        let result = remove([folder, lookalike])

        XCTAssertEqual(result.removed, [folder],
                       "the folder itself did not move, so nothing here is about ancestry")
        XCTAssertEqual(result.refused.map(\.path), [lookalike],
                       "a path that only shares a prefix was reported as having gone with "
                       + "a folder that never contained it")
        XCTAssertEqual(result.refused.map(\.reason), [.missing])
    }

    // MARK: - Order

    /// The batch's answer may not depend on the order it arrived in. `DiskEngine`
    /// hands over a `Set`, whose order is a hash seed — the same basket gave two
    /// different answers on two runs before the sort went in.
    ///
    /// Asserted absolutely as well as across the two orders: two wrong answers
    /// of equal size satisfy a comparison, so each order is also checked against
    /// what the tree really holds.
    func testAFolderAndAFileInsideItAnswerTheSameInEitherOrder() throws {
        var answers: [HelmTrash.Result] = []
        for (index, parentFirst) in [true, false].enumerated() {
            let name = "Ghost\(index)"
            let child = try write("\(name)/inside.bin", in: root, bytes: 120_000).path
            let folder = root.appendingPathComponent(name).path
            let order = parentFirst ? "parent first" : "child first"

            let result = remove(parentFirst ? [folder, child] : [child, folder])

            XCTAssertEqual(Set(result.removed), [folder, child],
                           "\(order): \(result.removed) — a child taken with its parent is "
                           + "neither a refusal nor silence")
            XCTAssertEqual(result.refused, [], "\(order)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder), "\(order)")
            XCTAssertGreaterThanOrEqual(result.freedBytes, 120_000, "\(order): nothing weighed")
            XCTAssertLessThan(result.freedBytes, 240_000,
                              "\(order): the file inside was counted twice, once for the "
                              + "folder and once for itself")
            answers.append(result)
        }
        XCTAssertEqual(answers[0].freedBytes, answers[1].freedBytes,
                       "the same basket freed two different amounts depending on the order "
                       + "it arrived in")
    }

    // MARK: - A symlink

    /// A leftover is often a symlink — a helper's cache linked into an app's
    /// own folder. Trashing the link frees the link, and what it points at is
    /// still there taking up the space. Claiming the target's bytes would tell
    /// somebody they got back 400 KB that never left the disk, and walking the
    /// link would also mean a link pointing outside the scope was measured
    /// through a gate it never passed.
    func testTrashingASymlinkFreesTheLinkAndNotWhatItPointsAt() throws {
        try write("Real/big.bin", in: root, bytes: 400_000)
        let target = root.appendingPathComponent("Real")
        let link = root.appendingPathComponent("Link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertGreaterThanOrEqual(FileWeight.allocated(of: target), 400_000,
                                    "the target weighs nothing, so the comparison below "
                                    + "is between two zeroes")

        let result = remove([link.path])

        XCTAssertEqual(result.removed, [link.path])
        XCTAssertLessThan(result.freedBytes, 400_000,
                          "the link was weighed by following it — the bytes reported freed "
                          + "are still on the disk")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path),
                      "the target went with the link")
    }

    // MARK: - Names

    /// The name is the caller's key back into its own list: a row is matched to
    /// its outcome by string equality. So whatever a filename is made of, the
    /// string that comes back is the string that went in — the normalisation
    /// that strips a trailing separator must not touch anything else.
    func testEveryKindOfNameComesBackSpelledExactlyAsItWentIn() throws {
        let names = ["two words.bin", "с кириллицей.bin", "emoji 🗑️.bin",
                     "with\ta tab.bin", ".hidden", "trailing dot.", "dash-—-dash.bin",
                     "quote'and\"quote.bin"]
        var paths: [String] = []
        for name in names { paths.append(try write("Names/" + name, in: root, bytes: 1_024).path) }

        let result = remove(paths)

        XCTAssertEqual(Set(result.removed), Set(paths),
                       "a name came back changed or not at all: "
                       + "\(Set(paths).symmetricDifference(result.removed).sorted())")
        XCTAssertEqual(result.refused, [])
        XCTAssertEqual(Set(moved), Set(paths))
    }

    // MARK: - Nothing, and nothing but refusals

    /// An empty basket is not an error and not a crash: no removals, no
    /// refusals, nothing freed.
    func testAnEmptyBatchAnswersEmptily() {
        let result = remove([])

        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.refused, [])
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertEqual(moved, [])
    }

    /// A basket the gate turned away entirely still produces its refusals. The
    /// refusals have to arrive with the batch or the count and the list
    /// disagree, and "the batch" can be nothing but refusals.
    func testABatchThatIsNothingButRefusalsStillReportsThem() {
        let result = remove([], outOfScope: ["/System/Library/CoreServices", "/usr/bin/env"])

        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.refused.map(\.reason), [.outOfScope, .outOfScope])
        XCTAssertEqual(result.failed, ["/System/Library/CoreServices", "/usr/bin/env"])
        XCTAssertEqual(result.freedBytes, 0)
        XCTAssertEqual(moved, [], "a path the gate refused was moved anyway")
    }
}
