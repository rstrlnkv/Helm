import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// What the batch is removed *around* is every copy that stays, and the engine
/// has to be told which those are.
///
/// `EveryCopyThatStaysSeedsTheLedgerTests` states the harm: an extra the person
/// left unticked goes on holding its family's blocks, so a clone of it that goes
/// frees nothing, while the banner promised the whole allocation. What that test
/// asks of the engine is the one thing no engine can answer — `staying.bin` is
/// named in no plan, and `HelmTrash`'s own doc says why it cannot be worked out
/// from the disk: "there is no reverse lookup from a family to its members". So
/// the fact travels: `DuplicateRemovalRequest` carries the copies that stay, and
/// what is tested here is that the engine seeds the ledger with them and with
/// everything else in the batch that is not going.
///
/// Real `clonefile`, for the reason the two suites above give: a fixture where a
/// clone's bytes are zero cannot see any of this, because a clone reports its
/// whole allocated size.
final class TheBatchIsToldWhatStaysTests: XCTestCase {

    private var root: URL!
    /// The copy the policy keeps — a plain copy, sharing blocks with nothing.
    private var survivor: String!
    /// An extra the person left unticked, in no plan, holding the family below.
    private var staying: String!
    /// The marked extra: a clone of `staying`, not of `survivor`.
    private var marked: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = scratchDirectory("told-what-stays")
        survivor = try write("survivor.bin", in: root, bytes: 4_000_000, filler: 9).path
        staying = try write("staying.bin", in: root, bytes: 4_000_000, filler: 9).path
        marked = root.appendingPathComponent("marked.bin").path
        try XCTSkipUnless(clonefile(staying, marked, 0) == 0,
                          "this volume does not clone; the arithmetic under test cannot arise")
    }

    private func engine() -> DuplicatesEngine {
        DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
    }

    /// The fixture is what it claims to be — without this every assertion below
    /// passes on a volume with no clone families at all.
    func testTheUntickedExtraAndTheMarkedOneAreOneFamily() throws {
        let family = try XCTUnwrap(CloneShare.familyID(ofFileAt: staying))
        XCTAssertEqual(CloneShare.familyID(ofFileAt: marked), family)
        XCTAssertNotEqual(CloneShare.familyID(ofFileAt: survivor), family,
                          "the survivor would then cover this family by accident")
    }

    /// The page's own arithmetic, which is what the banner has to agree with.
    private var bar: Int {
        DuplicateGroup.reclaimable(marking: [marked], in: [DuplicateGroup(copies:
            [survivor, staying, marked].map { path in
                DuplicateGroup.Copy(path: path,
                                    bytes: FileWeight.allocated(of: URL(fileURLWithPath: path)),
                                    cloneFamily: CloneShare.familyID(ofFileAt: path))
            })])
    }

    /// Told about the copy that merely stays, the banner says what the bar
    /// promised: nothing, because the family goes on being held.
    func testACopyThatMerelyStaysHoldsItsFamily() async throws {
        XCTAssertEqual(bar, 0, "precondition: the page already promises nothing here")

        let result = await engine().trash([DuplicatePlan(remove: marked, keep: survivor)],
                                          staying: [survivor, staying])

        XCTAssertEqual(result.removed, [marked], "precondition: the batch was accepted")
        XCTAssertEqual(result.freedBytes, bar,
                       "the banner promised the clone's whole allocation while its twin, an "
                       + "extra the person left unticked, goes on holding the family's blocks")
    }

    /// And the same seed read from the other side: a family with nothing left
    /// behind still gives its blocks back once, so the repair is not «seed
    /// everything».
    func testAFamilyWithNothingLeftBehindIsStillFreedOnce() async throws {
        let allocated = FileWeight.allocated(of: URL(fileURLWithPath: marked))
        XCTAssertGreaterThan(allocated, 0, "precondition: the clone occupies something")

        let result = await engine().trash([DuplicatePlan(remove: staying, keep: survivor),
                                           DuplicatePlan(remove: marked, keep: survivor)],
                                          staying: [survivor])

        XCTAssertEqual(Set(result.removed), [staying, marked], "precondition: both were accepted")
        XCTAssertEqual(result.freedBytes, allocated,
                       "one family with no survivor at all, counted once and not once per member")
    }

    /// A copy the batch **refused** stays too, and holds its family exactly as an
    /// unticked one does.
    ///
    /// The refusal here is the module's ordinary one — the pair stopped matching
    /// — because that is the reachable shape: two clone twins marked together, a
    /// permission or an edit takes one of them out of the batch, and the other
    /// goes on to free nothing at all. `staying` is deliberately **not** passed:
    /// what is under test is the batch's own knowledge of what it did not
    /// remove, and a refused path named in the caller's list too would prove
    /// only that the caller said it.
    func testACopyRefusedByTheBatchHoldsItsFamilyToo() async throws {
        // A copy the twins are identical to, and one they are not: the plan
        // against the second is refused, so its twin stays.
        let other = try write("other.bin", in: root, bytes: 4_000_000, filler: 4).path

        let result = await engine().trash([DuplicatePlan(remove: staying, keep: other),
                                           DuplicatePlan(remove: marked, keep: survivor)])

        XCTAssertEqual(result.removed, [marked], "precondition: only the matching pair went")
        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan],
                       "precondition: the other was refused for the reason this fixture builds")
        XCTAssertEqual(result.freedBytes, 0, """
            the refused copy is still on the disk holding the family's blocks, and the banner \
            charged the copy that went in full
            """)
    }
}
