import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A tick reaches the bar of the work it belongs to and no other: the removal's
/// while it runs, the search's while it searches, and none that arrives after
/// the search it came from was cancelled or replaced.
///
/// The fakes of this target report their ticks before they park, so none of them
/// can deliver one late; this work holds the search and reports a tick only when
/// the test lets it, which is the order a real walk can take when the engine's
/// cancel lands between two hashes.
@MainActor
final class ATickReachesOnlyItsOwnBarTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
    }

    /// Parks `find`, then reports one tick and answers nil (a cancelled search).
    private final class LateTickWork: DuplicatesWork, @unchecked Sendable {
        private let lock = NSLock()
        private var gate: CheckedContinuation<Void, Never>?
        var parked: Bool { lock.withLock { gate != nil } }

        func find(under path: String, keeping policy: KeepPolicy,
                  progress: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateFindings? {
            await withCheckedContinuation { c in lock.withLock { gate = c } }
            progress?(DuplicateProgress(candidates: 9, hashed: 4))
            return nil
        }
        func release() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { gate = nil }
                return gate
            }
            c?.resume()
        }
        func cancel() {}
        func trash(_ plans: [DuplicatePlan], staying: [String],
                   progress: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateRemoval {
            DuplicateRemoval(removed: [], refused: [], freedBytes: 0)
        }
        func stopRemoval() {}
        func backgroundScan() async -> ScanReport? { nil }
    }

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

    func testATickAfterCancelDoesNotReachTheStartScreen() async {
        let work = LateTickWork()
        let dvm = duplicatesModel(over: work)
        dvm.search()
        for _ in 0..<1000 where !work.parked { await Task.yield() }
        XCTAssertTrue(work.parked, "precondition: the search is in flight")

        dvm.cancel()
        work.release()
        await settle()

        XCTAssertEqual(dvm.phase, .start)
        XCTAssertNil(dvm.progress, "a late tick of a cancelled search is on the start screen")
    }

    func testATickAfterTheNextSearchStartedIsNotTheNextSearchsTick() async {
        let work = LateTickWork()
        let dvm = duplicatesModel(over: work)
        dvm.search()
        for _ in 0..<1000 where !work.parked { await Task.yield() }
        dvm.cancel()
        dvm.search()
        work.release()
        await settle()

        XCTAssertNil(dvm.progress, "the older search's tick landed on the newer search")
    }
}
