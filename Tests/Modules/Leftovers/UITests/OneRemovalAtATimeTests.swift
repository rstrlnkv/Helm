import XCTest
import HelmTestSupport
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// Pressing "Move to Trash" twice must not send the batch twice.
///
/// The two removal buttons go dark only when the selection is empty, and the
/// selection is not emptied until the rescan that *follows* the removal has come
/// back, so between the press and that moment the button is live and the paths
/// are still in `selected`.
///
/// What a second press would cost is not a second deletion — the files are
/// already in the Trash — but a **wrong report about the first**: `HelmTrash`
/// answers a path no longer there with a refusal, so the second round returns
/// `removed: []` and a failure per file, and would overwrite `failures`,
/// `removedCount` and `banner`.
///
/// **A fake that answers synchronously releases the gate before the call it is
/// gating returns**, so a test built on one passes whether or not the gate
/// exists. The fake below does not answer until it is told to.
@MainActor
final class OneRemovalAtATimeTests: XCTestCase {

    /// Answers `scan` at once and holds `trash` open until released, so a
    /// second press really does arrive while the first is still in flight.
    private final class HeldWork: LeftoversWork, @unchecked Sendable {
        private(set) var trashRequests = 0
        /// Counted for the same reason as the two below, and one more: the rescan
        /// `trash` makes *itself* is a scan too, so a guard that refused every scan
        /// while a removal runs would leave the list claiming what the removal has
        /// just taken away. A fake that cannot count these cannot tell the guard
        /// from the breakage.
        private(set) var scanRequests = 0
        /// The other request a control on this page makes, counted for the same
        /// reason: «Turn off» must not run during a removal.
        private(set) var setDisabledRequests = 0
        private let released = AsyncStream<Void>.makeStream()
        let items: [StaleItem]

        init(items: [StaleItem]) { self.items = items }

        func release() { released.continuation.finish() }

        func scan() async -> [StaleItem] {
            scanRequests += 1
            return items
        }

        func trash(_ paths: [String]) async -> LeftoversRemoval {
            trashRequests += 1
            // Hangs until `release()`. A `return` here would clear the flag
            // before the caller resumed, and the gate would be untested.
            for await _ in released.stream {}
            return LeftoversRemoval(removed: [], refused: [], freedBytes: 0)
        }

        func setDisabled(_ request: LeftoversToggle) async {
            setDisabledRequests += 1
        }
    }

    private func item(_ path: String) -> StaleItem {
        StaleItem(path: path, identifier: "com.acme.\(path)", kind: .launchAgent,
                  sizeBytes: 4_096, status: .orphaned)
    }

    func testASecondPressWhileTheFirstIsStillRunningIsRefused() async throws {
        let work = HeldWork(items: [item("/tmp/one.plist"), item("/tmp/two.plist")])
        let model = LeftoversViewModel(work: work)
        await model.scan()
        model.selected = Set(model.selectablePaths)
        XCTAssertFalse(model.selected.isEmpty, "precondition: something is ticked")

        let first = Task { await model.removeSelected() }
        // Let the first reach the fake and suspend inside it.
        await waitUntil("the removal reaches the fake") { work.trashRequests == 1 }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the first removal is in flight")

        // The second press is a task as well: without the gate it reaches the
        // held fake and stays there, so awaiting it here would hang the
        // test rather than fail it.
        var done = false
        let second = Task { await model.removeSelected(); done = true }
        await waitUntil("the refused second press completes") { done }

        XCTAssertEqual(work.trashRequests, 1,
                       "the batch was sent twice. The second round finds every path already "
                       + "in the Trash, so it comes back with a refusal for each one and "
                       + "overwrites the report of the removal that worked")

        work.release()
        _ = await (first.value, second.value)
    }

        /// And the flag has to say so, or the page cannot dim the button.
    func testTheModelSaysItIsBusyWhileARemovalRuns() async throws {
        let work = HeldWork(items: [item("/tmp/one.plist")])
        let model = LeftoversViewModel(work: work)
        await model.scan()
        model.selected = Set(model.selectablePaths)

        let running = Task { await model.removeSelected() }
        await waitUntil("the removal reaches the fake") { work.trashRequests == 1 }

        XCTAssertTrue(model.busy, "nothing on the page can tell that a removal is running")

        work.release()
        await running.value
        XCTAssertFalse(model.busy, "the flag outlived the work it describes")
    }

    // MARK: - The other three controls

    /// **«Turn off» does not run during a removal**: it asks launchd to switch a
    /// job off and then **rescans**, so a press during a removal would land a fresh
    /// `items` on top of the list the removal is about to report on.
    func testTurningARowOffWhileARemovalRunsIsRefused() async throws {
        let one = item("/tmp/one.plist")
        let work = HeldWork(items: [one])
        let model = LeftoversViewModel(work: work)
        await model.scan()
        model.selected = Set(model.selectablePaths)

        let removal = Task { await model.removeSelected() }
        await waitUntil("the removal reaches the fake") { work.trashRequests == 1 }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the removal is in flight")

        var done = false
        let press = Task { await model.setDisabled(true, item: one); done = true }
        await waitUntil("the refused switch press completes") { done }

        XCTAssertEqual(work.setDisabledRequests, 0,
                       "launchd was asked to switch a job off in the middle of a removal, and "
                       + "the rescan that follows lands on top of the removal's own report")

        work.release()
        _ = await (removal.value, press.value)
    }

    /// **Scan is refused during a removal** for the reason «Turn off» is: it
    /// rescans.
    ///
    /// **And the guard cannot be «no scanning while busy»**: `trash` holds `busy`
    /// across the rescan it makes *itself*, so such a guard would leave the list
    /// showing the rows the removal had just taken, under a report saying they
    /// are gone. So the second half of this test is a control: the rescan still
    /// arrives.
    func testAScanStartedByHandWhileARemovalRunsIsRefused() async throws {
        let one = item("/tmp/one.plist")
        let work = HeldWork(items: [one])
        let model = LeftoversViewModel(work: work)
        await model.scan()
        model.selected = Set(model.selectablePaths)
        let before = work.scanRequests
        XCTAssertEqual(before, 1, "precondition: the first scan reached the engine's place")

        let removal = Task { await model.removeSelected() }
        await waitUntil("the removal reaches the fake") { work.trashRequests == 1 }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the removal is in flight")

        var done = false
        let press = Task { await model.scan(); done = true }
        await waitUntil("the refused scan press completes") { done }

        XCTAssertEqual(work.scanRequests, before,
                       "the toolbar's Scan started a scan in the middle of a removal, and its "
                       + "fresh list lands on top of the one the removal is about to report on")

        work.release()
        _ = await (removal.value, press.value)

        XCTAssertEqual(work.scanRequests, before + 1,
                       "the rescan a removal makes for itself was refused with the rest — the "
                       + "list still shows the rows that have just gone to the Trash")
    }

    /// And the row's own delete: `.disabled(busy)` on a bar does not cover a menu
    /// inside a row.
    func testTheRowsOwnDeleteWhileARemovalRunsIsRefused() async throws {
        let one = item("/tmp/one.plist")
        let two = item("/tmp/two.plist")
        let work = HeldWork(items: [one, two])
        let model = LeftoversViewModel(work: work)
        await model.scan()
        model.selected = [one.path]

        let removal = Task { await model.removeSelected() }
        await waitUntil("the removal reaches the fake") { work.trashRequests == 1 }
        XCTAssertEqual(work.trashRequests, 1, "precondition: the removal is in flight")

        var done = false
        let fromTheMenu = Task { await model.remove(two); done = true }
        await waitUntil("the refused delete from the menu completes") { done }

        XCTAssertEqual(work.trashRequests, 1,
                       "a second batch went out from the row's menu while the first was still "
                       + "running, and its answer overwrites the report of the first")

        work.release()
        _ = await (removal.value, fromTheMenu.value)
    }
}
