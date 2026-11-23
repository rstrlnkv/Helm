import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// Stop removal is a promise that nothing moves; once the Trash has the batch
/// it cannot be kept, so the page stops offering it and the press reaches no work.
@MainActor
final class AStopIsNotOfferedOnceTheTrashHasTheBatchTests: XCTestCase {


    private func parkedRemoval(moving: Bool) async -> (AnsweringWork, DuplicatesViewModel, Task<Void, Never>) {
        let work = AnsweringWork(groups: [keepAndExtra()], movingWhileParked: moving)
        let dvm = await searchedModel(over: work)
        let removal = await parkRemoval(marking: extraCopy, in: dvm, over: work)
        return (work, dvm, removal)
    }

    func testOnceTheTrashHasTheBatchStopReachesNoWork() async {
        let (work, dvm, removal) = await parkedRemoval(moving: true)
        await waitUntil("dvm.moving", within: .seconds(5)) { dvm.moving }
        XCTAssertTrue(dvm.moving, "the model never learned the Trash has the batch")

        XCTAssertFalse(dvm.offersStop, "the page would still draw Stop")
        dvm.stopRemoval()
        await grace()
        XCTAssertFalse(work.calls.contains(.stopRemoval))

        work.releaseParked()
        await removal.value
        XCTAssertFalse(dvm.moving, "the flag outlived its removal")
    }

    /// The control: before `.moving`, the same press reaches the work.
    func testBeforeTheTrashHasTheBatchStopReachesTheWork() async {
        let (work, dvm, removal) = await parkedRemoval(moving: false)
        XCTAssertFalse(dvm.moving)
        XCTAssertTrue(dvm.offersStop, "the page would not draw Stop")

        dvm.stopRemoval()
        await waitUntil("the engine was told to stop the removal", within: .seconds(5)) { work.calls.contains(.stopRemoval) }
        XCTAssertTrue(work.calls.contains(.stopRemoval))

        work.releaseParked()
        await removal.value
    }
}
