import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A removal a person can stop, from the page's side of the port.
///
/// The engine obeys `stopRemoval` between files —
/// `ARemovalCanBeWatchedAndStoppedTests` proves that. This proves the page's
/// half: the Stop press reaches the engine as `stopRemoval`, and the page claims
/// nothing until the answer says what happened.
@MainActor
final class ARemovalShowsItsProgressAndStopsTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
    }

    // MARK: - Stop

    /// Stop during a removal reaches the engine as its own entry — not `cancel`,
    /// which reaches the search — and takes nothing off the screen: the reply
    /// decides what happened, not the press.
    func testStopReachesItsOwnEntryAndClaimsNothing() async {
        let work = AnsweringWork(groups: [group])
        let dvm = await searchedModel(over: work)
        dvm.toggleBasket(extra)
        work.answers(.park, to: .trash)
        let removal = Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        XCTAssertTrue(dvm.busy, "precondition: the removal is really in flight")

        dvm.stopRemoval()
        for _ in 0..<1000 where !work.calls.contains(.stopRemoval) { await Task.yield() }

        XCTAssertTrue(work.calls.contains(.stopRemoval))
        XCTAssertFalse(work.calls.contains(.cancel),
                       "stopping a removal silently cancelled the search too")
        XCTAssertTrue(dvm.busy, "the press claimed the removal was over before the reply said so")
        XCTAssertEqual(dvm.basket, [extra])

        work.releaseParked()
        await removal.value
    }

    // MARK: - Progress

    /// The removal's ticks reach the bar while it runs and leave with its answer.
    /// The search's ticks are a different pair, so a removal that painted the
    /// search's progress, or none, is told apart from one that paints its own.
    func testTheRemovalsTicksReachTheBarAndLeaveWithIt() async {
        let searchTick = DuplicateProgress(candidates: 100, hashed: 50)
        let removalTick = DuplicateProgress(candidates: 7, hashed: 3)
        let work = AnsweringWork(groups: [group], ticks: [searchTick], removalTicks: [removalTick])
        let dvm = await searchedModel(over: work)
        XCTAssertEqual(dvm.progress?.candidates, 100,
                       "precondition: the search's own tick is what the bar last held")
        dvm.toggleBasket(extra)
        work.answers(.park, to: .trash)
        let removal = Task { await dvm.emptyBasket() }
        for _ in 0..<1000 where work.parkedCount < 1 { await Task.yield() }
        for _ in 0..<1000 where dvm.progress == nil { await Task.yield() }

        XCTAssertTrue(dvm.busy, "precondition: the removal is really in flight")
        XCTAssertEqual(dvm.progress?.candidates, 7, "the bar shows nothing of the removal's own progress")
        XCTAssertEqual(dvm.progress?.hashed, 3)

        work.releaseParked()
        await removal.value
        XCTAssertFalse(dvm.busy)
        XCTAssertNil(dvm.progress, "the removal's last tick outlived its answer")
    }

    /// The same for a search: its tick is on the bar while it is parked. It is not
    /// cleared on the answer (only the next search, the cancel and the next
    /// removal clear it), and the page draws it only while searching or busy.
    func testTheSearchsTicksReachTheBar() async {
        let searchTick = DuplicateProgress(candidates: 100, hashed: 50)
        let work = AnsweringWork(groups: [group], ticks: [searchTick], answering: .park)
        let dvm = duplicatesModel(over: work)
        dvm.search()
        for _ in 0..<1000 where dvm.progress == nil { await Task.yield() }

        XCTAssertEqual(dvm.phase, .searching, "precondition: the search is in flight")
        XCTAssertEqual(dvm.progress?.candidates, 100)
        XCTAssertEqual(dvm.progress?.hashed, 50)

        work.releaseParked()
        for _ in 0..<1000 where dvm.phase != .result { await Task.yield() }
        XCTAssertEqual(dvm.phase, .result)
    }
}
