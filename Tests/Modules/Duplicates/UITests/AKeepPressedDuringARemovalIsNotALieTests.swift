import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A press that re-decides which copy stays, made while a removal that already
/// holds that copy is in flight, must not leave the page saying «stays» about a
/// file the engine then moves to the Trash (backlog M261).
///
/// `emptyBasket` captures its plans at the first line, so the request is out with
/// the extra in it. `keep`, `choose` and `toggleBasket` had no `busy` guard (the
/// neighbour `clearBasket` has one): `keep` pinned the extra, put it first and
/// unticked it, the reply then trashed it anyway. The person loses the copy they
/// had just chosen to keep, and the page showed the badge that says it was safe.
///
/// The expectation is the one `ClearSelectionIsNotAWayOutOfRemovalTests` holds:
/// the press is refused while `busy`, so what the page shows and what the engine
/// was asked to remove stay the same thing. A removal that is parked is the only
/// way into the window.
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
        dvm.toggleBasket(extra)
        XCTAssertEqual(dvm.basket, [extra], "precondition: the extra is marked")
        work.answers(.park, to: .trash)
        Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        XCTAssertEqual(work.parkedCount, 1, "precondition: the removal is in flight")
        XCTAssertTrue(dvm.busy, "precondition: the model knows")
        return (dvm, work)
    }

    private func finish(_ dvm: DuplicatesViewModel, _ work: AnsweringWork) async {
        work.releaseParked()
        for _ in 0..<200 where dvm.busy { await Task.yield() }
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
        await finish(dvm, work)
    }

    func testUntickingACopyTheBatchHoldsIsRefused() async throws {
        let (dvm, work) = try await removalInFlight()

        dvm.toggleBasket(extra)

        assertAgrees(dvm, "toggleBasket")
        await finish(dvm, work)
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
            dvm.toggleBasket(held)
            XCTAssertEqual(dvm.basket, [held], "precondition: marked")
            work.answers(.park, to: .trash)
            Task { await dvm.emptyBasket() }
            for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
            XCTAssertTrue(dvm.busy, "precondition: in flight")

            dvm.choose(policy)

            XCTAssertEqual(dvm.groups.first?.paths.first, stays,
                           "\(policy): the page now says the copy in the batch stays")
            XCTAssertEqual(dvm.basket, [held],
                           "\(policy): the mark on the copy the engine is trashing came off")
            await finish(dvm, work)
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
        let filed = "\(home)/Documents/Trips/photo.jpg"
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
        dvm.toggleBasket(filed)
        XCTAssertEqual(dvm.basket, [filed], "precondition: the filed copy is marked")
        work.answers(.park, to: .trash)
        Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        XCTAssertTrue(dvm.busy, "precondition: in flight")
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
        await finish(dvm, work)
    }

    func testRestoringTheRecommendationWorksOnceTheRemovalIsAnswered() async throws {
        let (dvm, work, _, _) = try await pinnedGroupWithFiledCopyInTheBatch(answer: false)
        await finish(dvm, work)
        XCTAssertFalse(dvm.busy, "precondition: the removal came back")
        guard let group = dvm.groups.first else { return XCTFail("group gone") }

        dvm.restoreRecommendation(for: group)

        XCTAssertNotEqual(dvm.grounds(of: try XCTUnwrap(dvm.groups.first)), .byHand,
                          "the press did nothing after the answer")
    }
}
