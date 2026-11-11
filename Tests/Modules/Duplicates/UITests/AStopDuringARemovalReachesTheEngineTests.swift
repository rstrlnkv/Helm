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
final class AStopDuringARemovalReachesTheEngineTests: XCTestCase {

    private var survivor: String { "\(home)/Downloads/keep.bin" }
    private var extra: String { "\(home)/Downloads/extra.bin" }

    private var group: DuplicateGroup {
        DuplicateGroup(copies: [.init(path: survivor, bytes: 9_000_000),
                                .init(path: extra, bytes: 9_000_000)])
    }

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
}
