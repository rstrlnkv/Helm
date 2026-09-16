import AppKit
import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import SwiftUI
import XCTest
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// Pressing "Move to Trash" twice must not send the batch twice.
///
/// The Scan button was `.disabled(lvm.scanning)` and nothing else here was gated:
/// the two removal buttons go dark only when the selection is empty, and the
/// selection is not emptied until the rescan that *follows* the removal has
/// come back. Between the press and that moment the button is live and the
/// paths are still in `selected`. Six controls on this page can start work; the
/// last of them to be found was Scan itself, and its own reading is below.
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
        /// Counted for the same reason as the two below, and one more: the rescan
        /// `trash` makes *itself* is a scan too, so a guard that refused every scan
        /// while a removal runs would leave the list claiming what the removal has
        /// just taken away. A fake that cannot count these cannot tell the guard
        /// from the breakage.
        private(set) var scanRequests = 0
        /// The other command a control on this page sends, counted for the same
        /// reason: «Turn off» stayed live through the whole removal.
        private(set) var setDisabledRequests = 0
        private let released = AsyncStream<Void>.makeStream()
        let items: [StaleItem]

        init(items: [StaleItem]) { self.items = items }

        func release() { released.continuation.finish() }

        /// The enum rather than the raw names this switched on before: a fake
        /// answering strings of its own goes on answering after the module renames
        /// a command, and what it answers then is `Data()` — which this codebase
        /// spells «the module could not answer».
        func send(_ command: EngineCommand) async throws -> Data {
            switch LeftoversCommand(rawValue: command.name) {
            case .scan:
                scanRequests += 1
                return (try? JSONEncoder().encode(items)) ?? Data()
            case .trash:
                trashRequests += 1
                // Hangs until `release()`. A `return` here would clear the flag
                // before the caller resumed, and the gate would be untested.
                for await _ in released.stream {}
                return (try? JSONEncoder().encode(
                    LeftoversRemoval(removed: [], refused: [], freedBytes: 0))) ?? Data()
            case .setDisabled:
                setDisabledRequests += 1
                return Data()
            case .none:
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

    // MARK: - The other three controls

    /// **Five controls can start an act on this page and two of them dimmed.**
    /// «Turn off» is one of the three that stayed live, and it is not a harmless
    /// one: it asks launchd to switch a job off and then **rescans**, so a press
    /// during a removal lands a fresh `items` on top of the list the removal is
    /// about to report on.
    func testTurningARowOffWhileARemovalRunsIsRefused() async throws {
        let one = item("/tmp/one.plist")
        let transport = HeldTransport(items: [one])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await model.scan()
        model.selected = Set(model.selectablePaths)

        let removal = Task { await model.removeSelected() }
        for _ in 0..<50 where transport.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(transport.trashRequests, 1, "precondition: the removal is in flight")

        let press = Task { await model.setDisabled(true, item: one) }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(transport.setDisabledRequests, 0,
                       "launchd was asked to switch a job off in the middle of a removal, and "
                       + "the rescan that follows lands on top of the removal's own report")

        transport.release()
        _ = await (removal.value, press.value)
    }

    /// **Scan is the sixth**, and it was gated on `scanning` alone — which is
    /// nothing at all during a removal. What it costs is exactly what «Turn off»
    /// costs and the note on that test spells out: it rescans, so a fresh `items`
    /// lands on top of the list the removal is about to report on. The button is
    /// on screen for the whole request, at the end of the toolbar.
    ///
    /// **And the guard cannot be «no scanning while busy»**, which is the shape
    /// the other five take: `trash` holds `busy` across the rescan it makes
    /// *itself*, so a guard written that way would leave the list showing the rows
    /// the removal had just taken, under a report saying they are gone. So the
    /// second half of this test is a control: the rescan still arrives.
    func testAScanStartedByHandWhileARemovalRunsIsRefused() async throws {
        let one = item("/tmp/one.plist")
        let transport = HeldTransport(items: [one])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await model.scan()
        model.selected = Set(model.selectablePaths)
        let before = transport.scanRequests
        XCTAssertEqual(before, 1, "precondition: the first scan reached the transport")

        let removal = Task { await model.removeSelected() }
        for _ in 0..<50 where transport.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(transport.trashRequests, 1, "precondition: the removal is in flight")

        let press = Task { await model.scan() }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(transport.scanRequests, before,
                       "the toolbar's Scan started a scan in the middle of a removal, and its "
                       + "fresh list lands on top of the one the removal is about to report on")

        transport.release()
        _ = await (removal.value, press.value)

        XCTAssertEqual(transport.scanRequests, before + 1,
                       "the rescan a removal makes for itself was refused with the rest — the "
                       + "list still shows the rows that have just gone to the Trash")
    }

    /// **And the page has to say so**, or the model's refusal is a press that does
    /// nothing — «the model refuses; the page dims. Both, or neither is reliable.»
    ///
    /// This was read off the drawing, as ink in the page's own 48 pt strip:
    /// measured before the fix, 1 272 404 idle and 1 272 404 busy. Scan has since
    /// moved into the settings window's toolbar (2026-09-16), which a page drawn
    /// on its own does not have, so the ink is out of reach and the claim is
    /// read off the construction instead: the button is disabled by the very
    /// flag `LeftoversViewModel.scan` refuses on. The model's half is the case
    /// above. What this cannot prove is that macOS draws a disabled toolbar
    /// item dimmed — which is the system's promise, not this page's.
    func testTheToolbarsScanGoesDimWhileARemovalRuns() throws {
        let page = "Sources/Modules/Leftovers/UI/LeftoversSettingsPage.swift"
        let code = SwiftSource.code(try RepoSource.text(of: page))
        // A computed property rather than a `func`, which `SwiftSource`'s body
        // reader does not cover: from the declaration to its matching brace.
        let declaration = try XCTUnwrap(code.range(of: "var scanButton"),
                                        "\(page) no longer declares scanButton")
        var depth = 0, opened = false
        var end = declaration.upperBound
        for index in code[declaration.upperBound...].indices {
            let character = code[index]
            if character == "{" { depth += 1; opened = true }
            if character == "}" { depth -= 1 }
            if opened && depth == 0 { end = code.index(after: index); break }
        }
        let button = String(code[declaration.lowerBound..<end])
        XCTAssertTrue(button.contains("lvm.scan()"),
                      "scanButton no longer scans — the rule below would pass over a button "
                      + "that does something else")
        XCTAssertTrue(button.contains(".disabled(") && button.contains("lvm.busy"), """
            Scan is not disabled by `lvm.busy`, so it stays live under a press the model now \
            refuses while a removal runs — a button that does nothing.
            """)
    }

    /// And the row's own delete, which is the control the Uninstaller's pass found
    /// last: `.disabled(busy)` on a bar does not cover a menu inside a row.
    func testTheRowsOwnDeleteWhileARemovalRunsIsRefused() async throws {
        let one = item("/tmp/one.plist")
        let two = item("/tmp/two.plist")
        let transport = HeldTransport(items: [one, two])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))
        await model.scan()
        model.selected = [one.path]

        let removal = Task { await model.removeSelected() }
        for _ in 0..<50 where transport.trashRequests == 0 { await Task.yield() }
        XCTAssertEqual(transport.trashRequests, 1, "precondition: the removal is in flight")

        let fromTheMenu = Task { await model.remove(two) }
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(transport.trashRequests, 1,
                       "a second batch went out from the row's menu while the first was still "
                       + "running, and its answer overwrites the report of the first")

        transport.release()
        _ = await (removal.value, fromTheMenu.value)
    }
}
