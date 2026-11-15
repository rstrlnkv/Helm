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
                   progress: (@Sendable (RemovalTick) -> Void)?) async -> DuplicateRemoval {
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
        let work = AnsweringWork(groups: [keepAndExtra()], ticks: [searchTick], removalTicks: [removalTick])
        let dvm = await searchedModel(over: work)
        XCTAssertEqual(dvm.progress?.candidates, 100,
                       "precondition: the search's own tick is what the bar last held")
        let removal = await parkRemoval(marking: extraCopy, in: dvm, over: work)
        await waitUntil("dvm.progress != nil", within: .seconds(5)) { dvm.progress != nil }

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
        let work = AnsweringWork(groups: [keepAndExtra()], ticks: [searchTick], answering: .park)
        let dvm = duplicatesModel(over: work)
        dvm.search()
        await waitUntil("dvm.progress != nil", within: .seconds(5)) { dvm.progress != nil }

        XCTAssertEqual(dvm.phase, .searching, "precondition: the search is in flight")
        XCTAssertEqual(dvm.progress?.candidates, 100)
        XCTAssertEqual(dvm.progress?.hashed, 50)

        work.releaseParked()
        await waitUntil("dvm.phase == .result", within: .seconds(5)) { dvm.phase == .result }
        XCTAssertEqual(dvm.phase, .result)
    }

    func testATickAfterCancelDoesNotReachTheStartScreen() async {
        let work = LateTickWork()
        let dvm = duplicatesModel(over: work)
        dvm.search()
        await waitUntil("work.parked", within: .seconds(5)) { work.parked }
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
        await waitUntil("work.parked", within: .seconds(5)) { work.parked }
        dvm.cancel()
        dvm.search()
        work.release()
        await settle()

        XCTAssertNil(dvm.progress, "the older search's tick landed on the newer search")
    }
}
