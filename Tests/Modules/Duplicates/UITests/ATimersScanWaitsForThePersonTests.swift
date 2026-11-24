import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The timer's scan and the person's search share the engine's one finder slot,
/// so a scan that fired mid-search would end the search with «Search stopped».
/// While a search or a removal runs the model answers nil, which the
/// coordinator treats as no completion.
@MainActor
final class ATimersScanWaitsForThePersonTests: XCTestCase {

    func testARunningSearchIsNotStoppedByTheTimersScan() async {
        let work = AnsweringWork(groups: [keepAndExtra()])
        work.answers(.park, to: .find)
        let dvm = duplicatesModel(over: work)
        dvm.search()
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
        XCTAssertEqual(work.parkedCount, 1, "precondition: the search is in flight")
        XCTAssertEqual(dvm.phase, .searching, "precondition: the model is searching")

        let report = await dvm.backgroundScan()

        XCTAssertNil(report)
        XCTAssertFalse(work.calls.contains(.backgroundScan))
        work.answers(.reply)
        work.releaseParked()
        await waitUntil("dvm.phase != .searching", within: .seconds(5)) { dvm.phase != .searching }
        XCTAssertEqual(dvm.phase, .result, "the search the person started landed")
    }

    func testARunningRemovalMakesTheTimersScanWait() async {
        let work = AnsweringWork(groups: [keepAndExtra()],
                                 removal: DuplicateRemoval(removed: [extraCopy],
                                                           refused: [], freedBytes: 9_000_000))
        let dvm = await searchedModel(over: work)
        await parkRemoval(marking: extraCopy, in: dvm, over: work)

        let report = await dvm.backgroundScan()

        XCTAssertNil(report)
        XCTAssertFalse(work.calls.contains(.backgroundScan))
        await releaseRemoval(dvm, work)
    }

    func testWhenThePersonIsDoneTheScanReachesTheWork() async {
        let work = AnsweringWork(groups: [keepAndExtra()])
        let dvm = await searchedModel(over: work)

        let report = await dvm.backgroundScan()

        XCTAssertNotNil(report)
        XCTAssertTrue(work.calls.contains(.backgroundScan))
    }
}
