import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// `TrashedLeftoversModel` sends one batch at a time: «The model refuses; the
/// page dims» (Architecture/Removal.md § One removal at a time).
///
/// A second press is not a second deletion but a wrong report about the
/// first: the second round finds every path gone and would overwrite
/// `failures`, `removedCount` and `outcome`.
///
/// The work does not answer until told to (`HeldWork`), or the test would pass
/// without the gate.
@MainActor
final class TheTrashOfferSendsOneBatchTests: XCTestCase {

    private func offer(_ id: String) -> TrashedAppLeftovers {
        TrashedAppLeftovers(
            bundleID: id, name: "Vendor Tool", appPath: "/Users/x/.Trash/\(id).app",
            leftovers: [Leftover(path: "\(NSHomeDirectory())/Library/Caches/\(id)",
                                 kind: .caches, sizeBytes: 2_048, matchedByName: false)])
    }

    private func opened(_ work: HeldWork) async -> TrashedLeftoversModel {
        let model = TrashedLeftoversModel(uvm: modelOver(work))
        await model.load()
        return model
    }

    // MARK: -

    func testASecondPressWhileTheFirstIsStillRunningIsRefused() async throws {
        let work = HeldWork(offers: [offer("com.vendor.tool")])
        let model = await opened(work)
        XCTAssertFalse(model.selected.isEmpty, "precondition: something is ticked")

        let first = Task { await model.removeSelection() }
        await waitUntil("the first batch is in flight") { work.trashRequests > 0 }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the first batch is in flight")

        // A task: without the gate the second press would wait on the held
        // work and hang the test rather than fail it.
        let second = Task { await model.removeSelection() }
        await grace()

        XCTAssertEqual(work.trashRequests, 1, """
            the batch went out twice. The second round finds every path already in the \
            Trash, comes back with a refusal for each, and its answer overwrites the report \
            of the removal that worked — the only place these files are ever named.
            """)

        work.release()
        _ = await (first.value, second.value)
    }

    /// The flag is up while the work runs, so the footer can dim.
    func testTheModelSaysItIsBusyWhileTheBatchIsInFlight() async throws {
        let work = HeldWork(offers: [offer("com.vendor.tool")])
        let model = await opened(work)

        let running = Task { await model.removeSelection() }
        await waitUntil("the first batch is in flight") { work.trashRequests > 0 }

        XCTAssertTrue(model.busy, "nothing in the window can tell that a removal is running")

        work.release()
        _ = await running.value
        XCTAssertFalse(model.busy, "the flag outlived the work it describes")
    }
}
