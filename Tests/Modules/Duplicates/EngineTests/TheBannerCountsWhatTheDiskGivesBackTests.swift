import Foundation
import XCTest
import HelmTestSupport
import HelmRuntime
@testable import Module_Duplicates_Engine

/// What the removal reports is what the disk gives back, and in this module the
/// copy that stays is never in the batch.
///
/// `FileWeight.Ledger` charges a clone family once — but only for the members it
/// sees, and its own doc says so: "there is no reverse lookup from a family to
/// its members, so a lone clone whose twin lives on elsewhere is still charged
/// in full." **Duplicates is the module where that is every family**: the
/// survivor is by construction excluded from the plan, so the ledger added to
/// `HelmTrash` for exactly this lie could never fire here, and trashing a clone
/// of a file that stays was reported as its full 20 MB against the 72 KB the
/// disk actually gains.
///
/// Measured on the fixture below rather than reasoned about: `clonefile` is what
/// Finder's Duplicate command does, and a clone reports its *whole* allocated
/// size, not zero — which is why "the clone's bytes are 0" fixtures elsewhere in
/// this target cannot see any of this.
final class TheBannerCountsWhatTheDiskGivesBackTests: XCTestCase {

    private var root: URL!
    private var original: String!
    private var clone: String!
    private var copy: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // `$TMPDIR` is on the data volume, which is APFS — `UserFileScope`
        // allows it, so the engine's own gate lets the batch through and the
        // refusal under test is not some other refusal wearing its clothes.
        root = scratchDirectory("clone-batch")
        original = try write("orig.bin", in: root, bytes: 4_000_000, filler: 7).path
        clone = root.appendingPathComponent("clone.bin").path
        try XCTSkipUnless(clonefile(original, clone, 0) == 0,
                          "this volume does not clone; the arithmetic under test cannot arise")
        copy = try write("copy.bin", in: root, bytes: 4_000_000, filler: 7).path
    }

    /// The fixture is what it claims to be. Every assertion below is about a
    /// family with a survivor outside the batch, and on a volume with no clones
    /// they would all pass for the wrong reason.
    func testTheFixtureIsACloneAndACopy() throws {
        let originalFamily = try XCTUnwrap(CloneShare.familyID(ofFileAt: original))
        XCTAssertEqual(CloneShare.familyID(ofFileAt: clone), originalFamily,
                       "the clone is not in the original's family")
        XCTAssertNotEqual(CloneShare.familyID(ofFileAt: copy), originalFamily,
                          "a plain copy shares blocks with nothing")
    }

    /// The removal the module actually performs: two extras go, the survivor
    /// stays, and only the copy that shares its blocks with nothing is space.
    func testACloneOfTheCopyThatStaysIsNotCountedAsFreed() async throws {
        let allocated = FileWeight.allocated(of: URL(fileURLWithPath: copy))
        XCTAssertGreaterThan(allocated, 0, "precondition: the copy occupies something")

        let result = await engine().trash([
            DuplicatePlan(remove: clone, keep: original),
            DuplicatePlan(remove: copy, keep: original),
        ])

        XCTAssertEqual(Set(result.removed), [clone, copy],
                       "precondition: the batch was accepted, so the figure is about it")
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertEqual(result.freedBytes, allocated,
                       "the banner promised the clone's blocks as well, and the disk keeps them "
                       + "for the copy that stays")
    }

    /// And a batch of nothing but clones of a survivor frees nothing at all —
    /// the whole press, honestly reported as zero.
    func testTwoClonesOfTheCopyThatStaysFreeNothing() async throws {
        let second = root.appendingPathComponent("clone-2.bin").path
        try XCTSkipUnless(clonefile(original, second, 0) == 0)

        let result = await engine().trash([
            DuplicatePlan(remove: clone, keep: original),
            DuplicatePlan(remove: second, keep: original),
        ])

        XCTAssertEqual(Set(result.removed), [clone, second], "precondition: both were accepted")
        XCTAssertEqual(result.freedBytes, 0)
    }

    /// The other three modules pass no survivor and are unchanged: a family with
    /// nobody staying gives its blocks back once, which is what the ledger has
    /// always done.
    func testAFamilyWithNoSurvivorInTheBatchStillGivesItsBlocksBackOnce() throws {
        let allocated = FileWeight.allocated(of: URL(fileURLWithPath: clone))
        XCTAssertGreaterThan(allocated, 0)

        let result = HelmTrash.remove(allowed: [original, clone], module: "test",
                                      trashing: { _ in })

        XCTAssertEqual(result.removed.count, 2, "precondition: both were weighed")
        XCTAssertEqual(result.freedBytes, allocated,
                       "one family, counted once — and not once per member")
    }

    /// The engine with its move replaced. Nothing here goes to anybody's Trash:
    /// what is under test is the arithmetic, which `HelmTrash` computes before
    /// the move and would compute the same way after it.
    private func engine() -> DuplicatesEngine {
        DuplicatesEngine(trashing: { _ in })
    }
}
