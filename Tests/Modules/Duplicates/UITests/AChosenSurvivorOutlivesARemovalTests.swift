import HelmContract
import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The copy somebody chose by hand is still the copy that stays after a removal
/// has taken one of that group's other copies.
///
/// **Why this is the case that breaks.** A pin is held by `DuplicateGroup.id`,
/// and that id is a digest of the group's paths — chosen so that pinning would
/// survive «the very rearrangement it records», which it does. It does not
/// survive a change of *membership*, and `emptyBasket` is exactly that: the reply
/// arrives, the group is rebuilt from the copies that are left, and the rebuilt
/// group has a different id. The set `pinned` then holds an id nothing on screen
/// answers to.
///
/// Nothing says so. The header stops reading «you chose this copy» and starts
/// giving a rung, and the next policy change — a popup, one click, no
/// confirmation — quietly hands the group back to the ladder and moves the
/// person's chosen copy out of first place. On this page first place is the
/// invariant everything else reads: `basketAllExtras` marks every copy after the
/// first, so the copy they chose to keep becomes one of the ticked ones.
///
/// The order of the gesture is the ordinary one. Choose which copy to keep, tick
/// the ones to remove, press the button — and the choice is spent on the press
/// that acts on it.
@MainActor
final class AChosenSurvivorOutlivesARemovalTests: XCTestCase {

    /// In the drop zone and the newest, so **both** policies would rather keep
    /// one of the others. That is what makes the pin the only thing holding it
    /// first, and the assertion below therefore about the pin rather than about
    /// a ladder that happens to agree.
    private let chosen = "\(home)/Downloads/photo.jpg"
    /// Filed and the oldest: what `.byPlace` and `.byDate` both keep.
    private let filed = "\(home)/Documents/Trips/photo.jpg"
    /// The third copy, and the one the removal takes.
    private let spare = "\(home)/Documents/Archive/photo.jpg"

    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private func trio() -> DuplicateGroup {
        DuplicateGroup(copies: [
            .init(path: chosen, bytes: 4_000_000, added: noon.addingTimeInterval(7200)),
            .init(path: filed, bytes: 4_000_000, added: noon),
            .init(path: spare, bytes: 4_000_000, added: noon.addingTimeInterval(3600)),
        ])
    }

    /// A page holding the trio, with `chosen` pinned by hand and `spare` ticked —
    /// and every step of getting there asserted, because a test about what
    /// survives a removal proves nothing if the choice was never made or the
    /// removal never happened.
    private func page() async throws -> (DuplicatesViewModel, DuplicatesWire) {
        let wire = DuplicatesWire(groups: [trio()],
                                  removal: DuplicateRemoval(removed: [spare], refused: [],
                                                            freedBytes: 4_000_000))
        let dvm = await searchedModel(over: wire)
        // A rule-produced order to start from: the fixture's own order is
        // whatever this file typed, and the wire hands it back unchanged.
        dvm.choose(.byDate)
        XCTAssertEqual(dvm.groups.first?.paths, [filed, spare, chosen],
                       "the ladder did not produce the order this test starts from")

        dvm.keep(chosen, in: try XCTUnwrap(dvm.groups.first))
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand,
                       "the choice this test is about was never recorded")

        dvm.toggleBasket(spare)
        XCTAssertEqual(dvm.basket, [spare], "the mark this removal acts on was never made")
        return (dvm, wire)
    }

    // MARK: - The removal itself

    func testTheRemovalTakesTheTickedCopyAndLeavesTheChosenOneFirst() async throws {
        let (dvm, wire) = try await page()

        await dvm.emptyBasket()

        XCTAssertTrue(wire.commands.contains(.trash), "no removal was attempted")
        XCTAssertEqual(dvm.groups.first?.paths, [chosen, filed],
                       "the removal did not prune the group this test is about")
    }

    // MARK: - What the pin does afterwards

    /// The header, which is the only thing on screen that says the choice is
    /// still in force.
    func testTheHeaderStillSaysTheCopyWasChosenByHand() async throws {
        let (dvm, _) = try await page()

        await dvm.emptyBasket()

        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand, """
            after a removal pruned the group, the page stopped saying its survivor was chosen by \
            hand — the pin is keyed by DuplicateGroup.id, which is a digest of the group's paths, \
            and removing a copy changes it
            """)
    }

    /// And the consequence, which costs a file rather than a sentence: the popup
    /// hands the group back to the ladder, and the copy the person chose to keep
    /// is no longer the copy `basketAllExtras` leaves alone.
    func testAPolicyChangeAfterTheRemovalStillLeavesTheChoiceStanding() async throws {
        let (dvm, _) = try await page()
        await dvm.emptyBasket()

        dvm.choose(.byPlace)

        XCTAssertEqual(dvm.groups.first?.paths.first, chosen, """
            the policy overruled a choice the person made about this group, because the removal \
            re-keyed it out of the pinned set
            """)
    }

    /// The same fact where it is a file rather than a row: «mark every extra
    /// copy» reads the array, so a survivor demoted by the policy is a copy in
    /// the basket.
    func testMarkingEveryExtraStillLeavesTheChosenCopyAlone() async throws {
        let (dvm, _) = try await page()
        await dvm.emptyBasket()
        dvm.choose(.byPlace)

        dvm.basketAllExtras()

        XCTAssertFalse(dvm.basket.contains(chosen), """
            the copy the person chose to keep was ticked for removal by the button that marks \
            every extra copy
            """)
    }

    // MARK: - The control

    /// The pin holds across a policy change when nothing was removed, so a
    /// failure above is about the removal and not about pinning generally. The
    /// same page, the same two `choose` calls, without the press in between.
    func testWithNoRemovalThePinHoldsAcrossThePolicyChange() async throws {
        let (dvm, wire) = try await page()

        dvm.choose(.byPlace)

        XCTAssertFalse(wire.commands.contains(.trash), "this control removed something")
        XCTAssertEqual(dvm.groups.first?.paths.first, chosen)
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand)
    }
}
