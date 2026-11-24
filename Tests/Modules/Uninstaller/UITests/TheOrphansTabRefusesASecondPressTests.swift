import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// `OrphansModel` refuses a second removal while one runs: «The model
/// refuses; the page dims» (Architecture/Removal.md § One removal at a time).
///
/// A second press is not a second deletion but a wrong report about the
/// first: every path comes back refused, and the last round to answer writes
/// `failures`, `removedCount` and `banner`.
///
/// The work does not answer until told to (`HeldWork`), or the test would pass
/// without the gate.
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
        await waitUntil("the first batch is in flight") { work.trashRequests > 0 }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the first batch is in flight")
        XCTAssertTrue(model.busy, "nothing on the tab can tell that a removal is running")

        // A task, so the second press is not awaited inline: the count below
        // is what fails when the guard is gone.
        let second = Task { await model.trashSelected() }
        await grace()

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
