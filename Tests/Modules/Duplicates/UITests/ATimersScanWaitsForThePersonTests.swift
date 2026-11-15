import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The timer's scan and the person's search share the engine's one finder slot,
/// so a scan that fired mid-search ended the search with «Search stopped». The
/// model now answers nil, which the coordinator treats as no completion, while a
/// search or a removal runs.
@MainActor
final class ATimersScanWaitsForThePersonTests: XCTestCase {

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: "\(home)/Downloads/keep.bin", bytes: 9_000_000),
                                .init(path: "\(home)/Downloads/extra.bin", bytes: 9_000_000)])
    }

    func testARunningSearchIsNotStoppedByTheTimersScan() async {
        let work = AnsweringWork(groups: [group])
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
        let work = AnsweringWork(groups: [group],
                                 removal: DuplicateRemoval(removed: ["\(home)/Downloads/extra.bin"],
                                                           refused: [], freedBytes: 9_000_000))
        let dvm = await searchedModel(over: work)
        dvm.toggleBasket("\(home)/Downloads/extra.bin")
        work.answers(.park, to: .trash)
        Task { await dvm.emptyBasket() }
        await waitUntil("work.parkedCount >= 1", within: .seconds(5)) { work.parkedCount >= 1 }
        XCTAssertTrue(dvm.busy, "precondition: a removal is running")

        let report = await dvm.backgroundScan()

        XCTAssertNil(report)
        XCTAssertFalse(work.calls.contains(.backgroundScan))
        work.answers(.reply)
        work.releaseParked()
        await waitUntil("!dvm.busy", within: .seconds(5)) { !dvm.busy }
    }

    func testWhenThePersonIsDoneTheScanReachesTheWork() async {
        let work = AnsweringWork(groups: [group])
        let dvm = await searchedModel(over: work)

        let report = await dvm.backgroundScan()

        XCTAssertNotNil(report)
        XCTAssertTrue(work.calls.contains(.backgroundScan))
    }
}
