import HelmRuntime
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// Changing what an extra copy *is* changes which copy stays, and the list on
/// screen is the answer to that question — so it is re-decided on the spot,
/// without hashing anything again.
///
/// **The mark that becomes the survivor is the mine here.** `emptyBasket` builds
/// its plans from each group's copies *after the first*, so a ticked path that
/// has just been promoted to survivor silently leaves the plans while staying in
/// the basket: the bar promises to remove four files and three go. The rule is
/// that the two agree, and it is asserted against the plans that actually reach
/// the wire rather than against a count.
@MainActor
final class PolicyChangeRearrangesTheListTests: XCTestCase {

    private let downloaded = "\(home)/Downloads/photo.jpg"
    private let filed = "\(home)/Documents/Trips/photo.jpg"

    /// One group: the copy in Downloads arrived first, the copy in Documents was
    /// filed later. The two policies disagree about it, which is the whole point
    /// of there being two.
    private func group() -> DuplicateGroup {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        return DuplicateGroup(copies: [
            .init(path: downloaded, bytes: 4_000_000, added: day),
            .init(path: filed, bytes: 4_000_000, added: day.addingTimeInterval(3600)),
        ])
    }

    private func model(_ wire: DuplicatesWire) -> DuplicatesViewModel {
        DuplicatesViewModel(vm: ModuleViewModel(transport: wire),
                            store: duplicatesStore(folder: "\(home)/Downloads"),
                            settings: SettingGuard(keys: PlantedSealKey()))
    }

    private func searched(_ wire: DuplicatesWire) async -> DuplicatesViewModel {
        let dvm = model(wire)
        dvm.search()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }
        return dvm
    }

    // MARK: - The list follows the answer

    func testTheFiledCopyStaysUnderByPlaceAndTheOlderOneUnderByDate() async {
        let dvm = await searched(DuplicatesWire(groups: [group()]))
        dvm.choose(.byDate)

        XCTAssertEqual(dvm.groups.first?.paths.first, downloaded,
                       "by date, the copy that arrived first is the one that stays")

        dvm.choose(.byPlace)

        XCTAssertEqual(dvm.groups.first?.paths.first, filed,
                       "by place, the copy somebody filed beats the one still in Downloads")
    }

    /// Re-decided, not re-read: the same copies, rearranged. A policy change that
    /// dropped a copy would be a search nobody ran.
    func testNothingIsLostWhenTheOrderChanges() async {
        let dvm = await searched(DuplicatesWire(groups: [group()]))
        dvm.choose(.byDate)

        XCTAssertEqual(Set(dvm.groups.flatMap(\.paths)), [downloaded, filed])
        XCTAssertEqual(dvm.groups.count, 1)
    }

    /// A search takes minutes, and the popup is live while it runs.
    ///
    /// The request carries the policy it was pressed with, so the engine's answer
    /// arrives ordered by *that* one. Landing it as it came would leave the list
    /// in one order while the sentence above it named another — and the header's
    /// reason, which asks the ladder rather than the array, would describe a copy
    /// that is not the one on the first row.
    func testAnAnswerThatLandsAfterThePolicyChangedIsPutInTheNewOrder() async {
        let wire = DuplicatesWire(groups: [group()], answering: .park)
        let dvm = model(wire)
        dvm.choose(.byDate)
        dvm.search()
        for _ in 0..<1000 where wire.parkedCount < 1 { await Task.yield() }

        dvm.choose(.byPlace)
        wire.releaseParked()
        for _ in 0..<200 where dvm.phase != .result { await Task.yield() }

        XCTAssertEqual(dvm.groups.first?.paths.first, filed,
                       "the list is in the order the request asked for, not the one on screen")
    }

    // MARK: - And the marks follow the list

    func testAMarkThatBecameTheSurvivorIsTakenOff() async {
        let dvm = await searched(DuplicatesWire(groups: [group()]))
        dvm.choose(.byDate)
        dvm.toggleBasket(filed)
        XCTAssertEqual(dvm.basket, [filed], "the mark this test is about was never made")

        dvm.choose(.byPlace)

        XCTAssertFalse(dvm.basket.contains(filed),
                       "the copy that now stays is still ticked for removal")
    }

    /// And it says so. The rearrangement happens to every group at once, most of
    /// them below the fold, so a mark quietly coming off is a change nobody sees.
    func testTakingAMarkOffIsReported() async {
        let dvm = await searched(DuplicatesWire(groups: [group()]))
        dvm.choose(.byDate)
        dvm.toggleBasket(filed)

        dvm.choose(.byPlace)

        XCTAssertEqual(dvm.marksNote, DupStr.unmarkedSurvivors(1))
    }

    func testAPolicyChangeThatMovesNoMarkSaysNothing() async {
        let dvm = await searched(DuplicatesWire(groups: [group()]))
        dvm.choose(.byDate)
        dvm.toggleBasket(filed)
        dvm.choose(.byPlace)
        XCTAssertNotNil(dvm.marksNote, "the note this test wants cleared was never drawn")

        dvm.choose(.byDate)

        XCTAssertNil(dvm.marksNote, "a note about the previous change outlived it")
    }

    /// The basket promises what the removal will do, and after a rearrangement
    /// that promise is the one most easily broken: the plans are built from the
    /// copies *after the first*, so a promoted survivor would leave the plans and
    /// stay in the count — the bar saying two files and one going.
    func testTheBasketAndThePlansAgreeAfterAPolicyChange() async throws {
        let wire = DuplicatesWire(groups: [trio()])
        let dvm = await searched(wire)
        dvm.choose(.byDate)
        dvm.toggleBasket(filed)
        dvm.toggleBasket(archived)
        XCTAssertEqual(dvm.basket.count, 2, "the marks this test is about were never made")

        dvm.choose(.byPlace)
        let promised = dvm.basket
        await dvm.emptyBasket()

        let plans = try XCTUnwrap(wire.removals.last, "no removal reached the wire at all")
        XCTAssertEqual(Set(plans.map(\.remove)), Set(promised),
                       "the bar counted a file the removal never asked for")
        XCTAssertEqual(Set(plans.map(\.keep)), [filed],
                       "every plan names the copy that stays, and it is the new one")
    }

    /// And whatever else is true, the copy that stays is never sent. The basket
    /// is a plain list of paths, so a survivor can end up in it — and this is the
    /// module's one promise: it never offers every copy of a file.
    func testTheCopyThatStaysIsNeverSentEvenWhenItIsMarked() async throws {
        let wire = DuplicatesWire(groups: [trio()])
        let dvm = await searched(wire)
        dvm.choose(.byPlace)
        let survivor = try XCTUnwrap(dvm.groups.first?.paths.first)
        dvm.basket = [survivor, archived]

        await dvm.emptyBasket()

        let plans = try XCTUnwrap(wire.removals.last, "no removal reached the wire at all")
        XCTAssertEqual(plans.map(\.remove), [archived])
        XCTAssertFalse(plans.map(\.remove).contains(survivor),
                       "the copy the page says stays was sent to the Trash")
    }

    private let archived = "\(home)/Documents/Archive/photo.jpg"

    /// Three copies, one in transit and two filed, so that a policy change moves
    /// the survivor *and* leaves an extra behind to be removed. With two copies
    /// the basket empties itself and `emptyBasket` never reaches the wire.
    private func trio() -> DuplicateGroup {
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        return DuplicateGroup(copies: [
            .init(path: downloaded, bytes: 4_000_000, added: day),
            .init(path: filed, bytes: 4_000_000, added: day.addingTimeInterval(3600)),
            .init(path: archived, bytes: 4_000_000, added: day.addingTimeInterval(7200)),
        ])
    }
}
