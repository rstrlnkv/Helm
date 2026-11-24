import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A press that re-decides which copy stays, made while a removal that already
/// holds that copy is in flight, must not leave the page saying «stays» about a
/// file the engine then moves to the Trash.
///
/// `emptyBasket` captures its plans at the first line, so the request is out with
/// the extra in it; an unguarded `keep` would pin the extra, put it first and
/// untick it, and the reply would trash the copy the person had just chosen to
/// keep. As in `ClearSelectionIsNotAWayOutOfRemovalTests`, the press is refused
/// while `busy`. A parked removal is the only way into the window.
@MainActor
final class AKeepPressedDuringARemovalIsNotALieTests: XCTestCase {

    /// Newest, in the drop zone: what the ladder keeps first under `.byPlace`
    /// is the filed one, under `.byDate` the oldest — the filed one both ways.
    private var survivor: String { "\(home)/Documents/Trips/photo.jpg" }
    /// The extra the removal in flight holds.
    private var extra: String { "\(home)/Downloads/photo.jpg" }
    private let noon = Date(timeIntervalSince1970: 1_700_000_000)

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [
            .init(path: survivor, bytes: 9_000_000, added: noon),
            .init(path: extra, bytes: 9_000_000, added: noon.addingTimeInterval(7200)),
        ])
    }

    private func removalInFlight() async throws -> (DuplicatesViewModel, AnsweringWork) {
        let work = AnsweringWork(groups: [group],
                                  removal: DuplicateRemoval(removed: [extra], refused: [],
                                                            freedBytes: 9_000_000))
        let dvm = await searchedModel(over: work)
        XCTAssertEqual(dvm.groups.first?.paths.first, survivor, "precondition: this copy stays")
        await parkRemoval(marking: extra, in: dvm, over: work)
        XCTAssertEqual(dvm.basket, [extra], "precondition: the extra is marked")
        XCTAssertEqual(work.parkedCount, 1, "precondition: the removal is in flight")
        return (dvm, work)
    }

    /// The page and the engine agree: if the extra was sent, the page must still
    /// show it as the one that goes — not first in its group, not unticked.
    private func assertAgrees(_ dvm: DuplicatesViewModel, _ what: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(dvm.groups.first?.paths.first, survivor,
                       "\(what): the page now says the copy in the batch stays", file: file, line: line)
        XCTAssertEqual(dvm.basket, [extra],
                       "\(what): the copy in the batch is no longer marked while the engine trashes it",
                       file: file, line: line)
    }

    func testKeepThisCopyIsRefusedForACopyTheBatchHolds() async throws {
        let (dvm, work) = try await removalInFlight()

        dvm.keep(extra, in: try XCTUnwrap(dvm.groups.first))

        assertAgrees(dvm, "keep")
        XCTAssertNotEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand,
                          "the header says the person chose the copy the engine is trashing")
        await releaseRemoval(dvm, work)
    }

    func testUntickingACopyTheBatchHoldsIsRefused() async throws {
        let (dvm, work) = try await removalInFlight()

        dvm.toggleBasket(extra)

        assertAgrees(dvm, "toggleBasket")
        await releaseRemoval(dvm, work)
    }

    /// The press itself, twice: the second «Remove» while the first is held sends
    /// nothing to the engine.
    func testASecondRemovePressWhileOneRunsSendsNothing() async throws {
        let (dvm, work) = try await removalInFlight()

        // Started, not awaited: with no guard the second press parks on the held
        // fake too, and awaiting it would hang instead of failing.
        let second = Task { await dvm.emptyBasket() }
        await grace()

        XCTAssertEqual(work.removals.count, 1, "a second removal reached the engine")
        await releaseRemoval(dvm, work)
        await second.value
    }

    /// A group where the two policies disagree, so one of them would put the
    /// in-flight extra first: the filed copy is the newer, the drop-zone copy the
    /// older. The batch holds the one the *other* policy would keep.
    func testAPolicyChangeCannotPromoteACopyTheBatchHolds() async throws {
        let oldDrop = "\(home)/Downloads/photo.jpg"
        let newFiled = "\(home)/Documents/Trips/photo.jpg"
        for (start, held, policy) in [(KeepPolicy.byDate, newFiled, KeepPolicy.byPlace)] {
            let work = AnsweringWork(
                groups: [DuplicateGroup(copies: [
                    .init(path: oldDrop, bytes: 9_000_000, added: noon),
                    .init(path: newFiled, bytes: 9_000_000, added: noon.addingTimeInterval(7200)),
                ])],
                removal: DuplicateRemoval(removed: [held], refused: [], freedBytes: 9_000_000))
            let dvm = await searchedModel(over: work)
            dvm.choose(start)
            let stays = try XCTUnwrap(dvm.groups.first?.paths.first)
            XCTAssertNotEqual(stays, held, "precondition: \(start) keeps the other copy")
            await parkRemoval(marking: held, in: dvm, over: work)
            XCTAssertEqual(dvm.basket, [held], "precondition: marked")

            dvm.choose(policy)

            XCTAssertEqual(dvm.groups.first?.paths.first, stays,
                           "\(policy): the page now says the copy in the batch stays")
            XCTAssertEqual(dvm.basket, [held],
                           "\(policy): the mark on the copy the engine is trashing came off")
            await releaseRemoval(dvm, work)
        }
    }

    /// Control: once the removal is answered, the press works again, so the
    /// guard is deferred nothing and the red cases above are about the window.
    func testKeepWorksOnceTheRemovalIsAnswered() async throws {
        let work = AnsweringWork(groups: [DuplicateGroup(copies: [
            .init(path: survivor, bytes: 9_000_000, added: noon),
            .init(path: extra, bytes: 9_000_000, added: noon.addingTimeInterval(7200)),
        ])], removal: DuplicateRemoval(removed: [], refused: [], freedBytes: 0))
        let dvm = await searchedModel(over: work)

        dvm.keep(extra, in: try XCTUnwrap(dvm.groups.first))

        XCTAssertEqual(dvm.groups.first?.paths.first, extra)
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand)
    }

    /// «Restore the recommendation» re-orders the group too. The person pinned the
    /// drop-zone copy by hand, so the filed one is the extra in the batch; the rule
    /// (`.byPlace`) would put the filed one first again. While the removal is in
    /// flight the press is refused; once it is answered, the same press works.
    private func pinnedGroupWithFiledCopyInTheBatch(answer removed: Bool = true) async throws
        -> (DuplicatesViewModel, AnsweringWork, stays: String, held: String) {
        let drop = "\(home)/Downloads/photo.jpg"
        let work = AnsweringWork(
            groups: [DuplicateGroup(copies: [
                .init(path: drop, bytes: 9_000_000, added: noon),
                .init(path: filed, bytes: 9_000_000, added: noon.addingTimeInterval(7200)),
            ])],
            removal: DuplicateRemoval(removed: removed ? [filed] : [], refused: [], freedBytes: 0))
        let dvm = await searchedModel(over: work)
        dvm.choose(.byDate)
        dvm.choose(.byPlace)
        XCTAssertEqual(dvm.groups.first?.paths.first, filed, "precondition: the rule keeps the filed copy")
        dvm.keep(drop, in: try XCTUnwrap(dvm.groups.first))
        XCTAssertEqual(dvm.groups.first?.paths.first, drop, "precondition: the person pinned the drop copy")
        await parkRemoval(marking: filed, in: dvm, over: work)
        XCTAssertEqual(dvm.basket, [filed], "precondition: the filed copy is marked")
        return (dvm, work, drop, filed)
    }

    func testRestoringTheRecommendationCannotPromoteACopyTheBatchHolds() async throws {
        let (dvm, work, stays, held) = try await pinnedGroupWithFiledCopyInTheBatch()
        let before = try XCTUnwrap(dvm.groups.first)

        dvm.restoreRecommendation(for: before)

        XCTAssertEqual(dvm.groups.first?.paths, before.paths, "the order moved under the running removal")
        XCTAssertEqual(dvm.groups.first?.paths.first, stays,
                       "the page now says the copy in the batch (\(held)) stays")
        XCTAssertEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand,
                       "the pin was released while the removal runs")
        await releaseRemoval(dvm, work)
    }

    func testRestoringTheRecommendationWorksOnceTheRemovalIsAnswered() async throws {
        let (dvm, work, _, _) = try await pinnedGroupWithFiledCopyInTheBatch(answer: false)
        await releaseRemoval(dvm, work)
        XCTAssertFalse(dvm.busy, "precondition: the removal came back")
        guard let group = dvm.groups.first else { return XCTFail("group gone") }

        dvm.restoreRecommendation(for: group)

        XCTAssertNotEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand,
                          "the press did nothing after the answer")
    }
}
