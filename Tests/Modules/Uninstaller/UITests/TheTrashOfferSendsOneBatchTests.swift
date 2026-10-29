import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Uninstaller_Engine
@testable import Module_Uninstaller_UI

/// **The fifth model that trashes, and the one the family guard once missed.**
///
/// «The model refuses; the page dims. Both, or neither is reliable» —
/// ARCHITECTURE.md § One removal at a time, stated once for the four view
/// models that send a trash command. `OneRemovalAtATimeEverywhereTests` enforces
/// it by reading every file under `Sources/Modules` that sends a removal
/// (`Command.trash` or `uvm.trashPaths(`), which `TrashedLeftoversView.swift` does
/// too; the model in it, `TrashedLeftoversModel`, is not called a view model and
/// was missed while the scan went by file name. It calls the model's `trashPaths`, and
/// it has `busy` for the footer to read with nothing standing beside the request:
/// `removeSelection` sets the flag and starts the batch whatever was already in
/// flight.
///
/// What a second press costs is not a second deletion — the files are already in
/// the Trash. It is a **wrong report about the first**: the second round finds
/// every path gone, comes back with a refusal apiece, and this model overwrites
/// `failures`, `removedCount` and `outcome` with it. The person is shown a list
/// of everything that moved, under a sentence saying it did not. This window is
/// the only place some of those files are ever named.
///
/// **The work does not answer until it is told to.** A fake that answers
/// synchronously releases the gate before the call it is gating returns, so a
/// test built on one passes whether or not the gate exists.
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
        for _ in 0..<50 where work.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the first batch is in flight")

        // A task as well: without the gate the second press reaches the held
        // work and stays there, so awaiting it here would hang the test
        // rather than fail it.
        let second = Task { await model.removeSelection() }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(work.trashRequests, 1, """
            the batch went out twice. The second round finds every path already in the \
            Trash, comes back with a refusal for each, and its answer overwrites the report \
            of the removal that worked — the only place these files are ever named.
            """)

        work.release()
        _ = await (first.value, second.value)
    }

    /// And the flag has to be up while the work runs, or the footer cannot dim
    /// anything — the other half of «both, or neither».
    func testTheModelSaysItIsBusyWhileTheBatchIsInFlight() async throws {
        let work = HeldWork(offers: [offer("com.vendor.tool")])
        let model = await opened(work)

        let running = Task { await model.removeSelection() }
        for _ in 0..<50 where work.trashRequests == 0 { await Task.yield() }

        XCTAssertTrue(model.busy, "nothing in the window can tell that a removal is running")

        work.release()
        _ = await running.value
        XCTAssertFalse(model.busy, "the flag outlived the work it describes")
    }
}
