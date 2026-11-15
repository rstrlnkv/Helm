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


    /// Stop during a removal reaches the engine as its own entry — not `cancel`,
    /// which reaches the search — and takes nothing off the screen: the reply
    /// decides what happened, not the press.
    func testStopReachesItsOwnEntryAndClaimsNothing() async {
        let work = AnsweringWork(groups: [keepAndExtra()])
        let dvm = await searchedModel(over: work)
        let removal = await parkRemoval(marking: extraCopy, in: dvm, over: work)

        dvm.stopRemoval()
        await waitUntil("the engine was told to stop the removal", within: .seconds(5)) { work.calls.contains(.stopRemoval) }

        XCTAssertTrue(work.calls.contains(.stopRemoval))
        XCTAssertFalse(work.calls.contains(.cancel),
                       "stopping a removal silently cancelled the search too")
        XCTAssertTrue(dvm.busy, "the press claimed the removal was over before the reply said so")
        XCTAssertEqual(dvm.basket, [extraCopy])

        work.releaseParked()
        await removal.value
    }
}
