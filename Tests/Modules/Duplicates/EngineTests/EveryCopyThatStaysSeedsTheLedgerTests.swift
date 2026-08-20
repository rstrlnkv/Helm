import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// What the batch is removed *around* is every copy that stays, not only the
/// survivors it was paired against.
///
/// `DuplicateGroup.reclaimable` — the fold the bar under the list, the
/// confirmation and `wasted` all read — says so outright: "What stays is every
/// copy that is not marked — not merely each group's survivor. A clone left
/// unticked holds its family's blocks exactly as the survivor does."
///
/// `DuplicatesEngine.trash` seeds `HelmTrash`'s ledger with
/// `Array(Set(plans.map(\.keep)))`, which is the survivors and nothing else. An
/// extra the person left unticked is in no plan, so its family is not seeded —
/// and a marked copy that shares its blocks with it is charged in full. The bar
/// before the press and the banner after it are then two arithmetics again,
/// which is the state `DuplicateGroup.reclaimable` was written to end: one
/// screen quoted 300 MB above the list and 321 MB below it about the same two
/// files.
///
/// **Ticking some of a group's extras is the ordinary case, not an exotic one.**
/// Finder's Duplicate command makes clones, so `photo.jpg`, `photo copy.jpg` and
/// `photo copy 2.jpg` in one folder are one family — and the filed original
/// somewhere else is the survivor the policy picks. Untick one of the three and
/// the disk gives back nothing at all.
///
/// Real `clonefile`, for the reason `TheBannerCountsWhatTheDiskGivesBackTests`
/// gives: a fixture where the clone's bytes are zero cannot see any of this,
/// because a clone reports its whole allocated size.
final class EveryCopyThatStaysSeedsTheLedgerTests: XCTestCase {

    private var root: URL!
    /// The copy the policy keeps — a plain copy, sharing blocks with nothing.
    private var survivor: String!
    /// An extra the person left **unticked**. It is in no plan, and it holds the
    /// family below.
    private var staying: String!
    /// The extra that is marked: a clone of `staying`, not of `survivor`.
    private var marked: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = scratchDirectory("copies-that-stay")
        survivor = try write("survivor.bin", in: root, bytes: 4_000_000, filler: 9).path
        staying = try write("staying.bin", in: root, bytes: 4_000_000, filler: 9).path
        marked = root.appendingPathComponent("marked.bin").path
        try XCTSkipUnless(clonefile(staying, marked, 0) == 0,
                          "this volume does not clone; the arithmetic under test cannot arise")
    }

    /// The fixture is what it claims to be. Without this every assertion below
    /// passes on a volume with no clone families at all.
    func testTheUntickedExtraAndTheMarkedOneAreOneFamily() throws {
        let family = try XCTUnwrap(CloneShare.familyID(ofFileAt: staying))
        XCTAssertEqual(CloneShare.familyID(ofFileAt: marked), family,
                       "the marked copy is not a clone of the one being left behind")
        XCTAssertNotEqual(CloneShare.familyID(ofFileAt: survivor), family,
                          "the survivor shares blocks with them, so the seed it does carry "
                          + "would cover this by accident")
    }

    /// The group as the page holds it, each copy with the facts the walk read.
    private func group() -> DuplicateGroup {
        DuplicateGroup(copies: [survivor, staying, marked].map { path in
            DuplicateGroup.Copy(path: path,
                                bytes: FileWeight.allocated(of: URL(fileURLWithPath: path)),
                                cloneFamily: CloneShare.familyID(ofFileAt: path))
        })
    }

    /// The bar's own answer, first: with one extra ticked and the other left
    /// alone, the press frees nothing, because the family goes on being held.
    func testTheBarPromisesNothingForACloneWhoseTwinIsLeftUnticked() {
        XCTAssertEqual(DuplicateGroup.reclaimable(marking: [marked], in: [group()]), 0, """
            the fold the page shows already disagrees with the disk, so the assertion below is \
            not about the engine at all
            """)
    }

    /// And the banner has to say the same thing. It does not: the ledger is
    /// seeded from the plans' survivors, and the copy that is really holding the
    /// blocks was never named.
    /// **The batch has to be told what stays, and now it can be.**
    ///
    /// This asked the engine for a fact nobody handed it: `staying.bin` appears
    /// in no plan, and `HelmTrash.remove`'s own doc records why it cannot be
    /// recovered from the disk — there is no reverse lookup from a clone family
    /// to its members, and `ATTR_CMNEXT_PRIVATESIZE` reads ~0 for each twin
    /// while both are present. So it was red under every implementation that
    /// did not change the wire.
    ///
    /// The wire changed: `trash` takes `staying:`, and the page fills it from
    /// every copy it is keeping rather than from each group's survivor. Told
    /// that, the same batch reports the nothing it frees.
    func testTheBannerSaysWhatTheBarPromisedRatherThanTheWholeClone() async throws {
        let bar = DuplicateGroup.reclaimable(marking: [marked], in: [group()])

        let result = await DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
            .trash([DuplicatePlan(remove: marked, keep: survivor)],
                   staying: [survivor, staying])

        XCTAssertEqual(result.removed, [marked],
                       "precondition: the batch was accepted, so the figure is about it")
        XCTAssertTrue(result.refused.isEmpty)
        XCTAssertEqual(result.freedBytes, bar, """
            the banner promised the clone's whole allocation while its twin — an extra the person \
            left unticked — goes on holding the family's blocks. The seed has to be every copy \
            that stays, not each group's survivor
            """)
    }

    /// The ledger can already answer this, which is what makes the assertion
    /// above a defect in the engine rather than a limit of `HelmTrash`: told
    /// about both copies that stay, the same batch reports the nothing it frees.
    ///
    /// Not a substitute for the test above — this one calls `HelmTrash` directly,
    /// so it proves the mechanism exists and says nothing about whether the
    /// engine uses it.
    func testTheLedgerAnswersCorrectlyWhenItIsToldAboutEveryCopyThatStays() {
        let result = HelmTrash.remove(allowed: [marked],
                                      sharedWith: [survivor, staying],
                                      module: "test", trashing: { _ in })

        XCTAssertEqual(result.removed, [marked], "precondition: the path was weighed")
        XCTAssertEqual(result.freedBytes, 0,
                       "the seed cannot express «this family is held by a copy that stays»")
    }

    /// The same seed read from the other side: a family whose members are all in
    /// the batch still gives its blocks back once, so the repair must not be «seed
    /// everything».
    func testAFamilyWithNothingLeftBehindIsStillFreedOnce() async throws {
        let allocated = FileWeight.allocated(of: URL(fileURLWithPath: marked))
        XCTAssertGreaterThan(allocated, 0, "precondition: the clone occupies something")

        let result = await DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
            .trash([DuplicatePlan(remove: staying, keep: survivor),
                    DuplicatePlan(remove: marked, keep: survivor)])

        XCTAssertEqual(Set(result.removed), [staying, marked], "precondition: both were accepted")
        XCTAssertEqual(result.freedBytes, allocated,
                       "one family with no survivor at all, counted once and not once per member")
    }
}
