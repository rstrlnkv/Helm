import HelmRuntime
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The Leftovers tab starts a removal from a `busy` flag with nothing
/// standing beside the request.**
///
/// «The model refuses; the page dims. Both, or neither is reliable» —
/// Architecture/Removal.md § One removal at a time. `OneRemovalAtATimeEverywhereTests`
/// (HelmAppTests) enforces it for every module by reading the files that send a
/// removal; this is the behavioural half for `OrphansModel`, which holds what
/// the eight of the tab's `@State`s that moved into it held, and so can be driven.
///
/// What a second press costs is not a second deletion — the files are already in
/// the Trash. It is a **wrong report about the first**: every path comes back
/// refused, and `trashSelected` writes `failures`, `removedCount` and `banner`
/// from whichever round answers last.
///
/// **The work does not answer until it is told to** (`HeldWork`): a fake that
/// answers synchronously releases the gate before the call it is gating
/// returns, so a test built on one passes whether or not the gate exists.
@MainActor
final class TheOrphansTabRefusesASecondPressTests: XCTestCase {

    func testASecondRemovalWhileTheFirstIsRunningIsRefused() async throws {
        let path = "\(NSHomeDirectory())/Library/Caches/com.gone.app"
        let work = HeldWork(
            orphans: [OrphanGroup(bundleID: "com.gone.app", leftovers: [
                Leftover(path: path, kind: .caches, sizeBytes: 2_048, matchedByName: false)])],
            removal: UninstallResult(trashed: [path], freedBytes: 2_048))
        let uvm = modelOver(work)
        let model = uvm.orphans
        await model.scan()
        model.toggleAll()
        XCTAssertEqual(model.selected, [path], "precondition: the leftover is ticked")

        let first = Task { await model.trashSelected() }
        for _ in 0..<50 where work.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the first batch is in flight")
        XCTAssertTrue(model.busy, "nothing on the tab can tell that a removal is running")

        // A task as well, so the second press is not awaited inline: the count
        // below is what fails when the guard is gone. A second request would
        // wait on `HeldWork`'s one `released` stream, which is shared by every
        // call; what that does to the run was not tried.
        let second = Task { await model.trashSelected() }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(work.trashRequests, 1, """
            the batch went out twice. The second round finds every path already in the \
            Trash, comes back with a refusal for each, and its answer overwrites the report \
            of the removal that worked.
            """)

        work.release()
        _ = await (first.value, second.value)

        XCTAssertFalse(model.busy, "the flag outlived the work it describes")
        XCTAssertEqual(model.removedCount, 1, "the report is the first round's")
        XCTAssertTrue(model.failures.isEmpty)
        XCTAssertNotNil(model.banner)
    }
}
