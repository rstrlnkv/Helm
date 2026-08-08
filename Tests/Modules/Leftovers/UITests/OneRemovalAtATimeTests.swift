import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// Pressing "Move to Trash" twice must not send the batch twice.
///
/// The Scan button is `.disabled(lvm.scanning)` and nothing else here is gated:
/// the two removal buttons go dark only when the selection is empty, and the
/// selection is not emptied until the rescan that *follows* the removal has
/// come back. Between the press and that moment the button is live and the
/// paths are still in `selected`.
///
/// What the second press costs is not a second deletion — the files are already
/// in the Trash — it is a **wrong report about the first**. `HelmTrash` answers
/// a path that is no longer there with a refusal and a reason, so the second
/// round returns `removed: []` and a failure per file, and this view model
/// overwrites `failures`, `removedCount` and `banner` with it. The person is
/// told nothing moved and shown a list of everything that did, in the one place
/// this module ever names a refusal.
///
/// Homebrew has had a gate for exactly this since its own pass, and the note on
/// that test applies here word for word: **a fake that answers synchronously
/// releases the gate before the call it is gating returns**, so a test built on
/// one passes whether or not the gate exists. The transport below does not
/// answer until it is told to.
@MainActor
final class OneRemovalAtATimeTests: XCTestCase {

    /// Answers `scan` at once and holds `trash` open until released, so a
    /// second press really does arrive while the first is still in flight.
    private final class HeldTransport: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        private(set) var trashRequests = 0
        private let released = AsyncStream<Void>.makeStream()
        let items: [StaleItem]

        init(items: [StaleItem]) { self.items = items }

        func release() { released.continuation.finish() }

        func send(_ command: EngineCommand) async throws -> Data {
            switch command.name {
            case LeftoversCommand.scan.rawValue:
                return (try? JSONEncoder().encode(items)) ?? Data()
            case LeftoversCommand.trash.rawValue:
                trashRequests += 1
                // Hangs until `release()`. A `return` here would clear the flag
                // before the caller resumed, and the gate would be untested.
                for await _ in released.stream {}
                return (try? JSONEncoder().encode(
                    LeftoversRemoval(removed: [], failed: [], freedBytes: 0))) ?? Data()
            default:
                return Data()
            }
        }
    }

    private func item(_ path: String) -> StaleItem {
        StaleItem(path: path, identifier: "com.acme.\(path)", kind: .launchAgent,
                  sizeBytes: 4_096, status: .orphaned)
    }

    func testASecondPressWhileTheFirstIsStillRunningIsRefused() async throws {
        let transport = HeldTransport(items: [item("/tmp/one.plist"), item("/tmp/two.plist")])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await model.scan()
        model.selected = Set(model.selectablePaths)
        XCTAssertFalse(model.selected.isEmpty, "precondition: something is ticked")

        let first = Task { await model.removeSelected() }
        // Let the first reach the transport and suspend inside it.
        for _ in 0..<50 where transport.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(transport.trashRequests, 1, "precondition: the first removal is in flight")

        // The second press is a task as well: without the gate it reaches the
        // held transport and stays there, so awaiting it here would hang the
        // test rather than fail it.
        let second = Task { await model.removeSelected() }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(transport.trashRequests, 1,
                       "the batch was sent twice. The second round finds every path already "
                       + "in the Trash, so it comes back with a refusal for each one and "
                       + "overwrites the report of the removal that worked")

        transport.release()
        _ = await (first.value, second.value)
    }

        /// And the flag has to say so, or the page cannot dim the button.
    func testTheModelSaysItIsBusyWhileARemovalRuns() async throws {
        let transport = HeldTransport(items: [item("/tmp/one.plist")])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await model.scan()
        model.selected = Set(model.selectablePaths)

        let running = Task { await model.removeSelected() }
        for _ in 0..<50 where transport.trashRequests == 0 { await Task.yield() }

        XCTAssertTrue(model.busy, "nothing on the page can tell that a removal is running")

        transport.release()
        await running.value
        XCTAssertFalse(model.busy, "the flag outlived the work it describes")
    }
}
