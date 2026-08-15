import HelmContract
import HelmRuntime
import HelmTestSupport
import HelmUI
import XCTest
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The engine acts on a timer and on files arriving, with the page open and
/// nobody pressing anything — and the page read the history exactly once, so an
/// hour of unattended work drew as nothing. The engine announces `history` now,
/// and the view model re-asks; these hold both halves of that seam.
@MainActor
final class ThePageHearsWhatTheEngineDidTests: XCTestCase {

    private let home = "/Users/x"

    private func model(on wire: AutopilotWire) -> AutopilotViewModel {
        AutopilotViewModel(vm: ModuleViewModel(transport: wire),
                           presetFolders: FakePresetFolders(home: home), home: home)
    }

    private func record(_ file: String, run: String) -> ActionRecord {
        ActionRecord(at: Date(), rule: "Sort", file: file, kind: .moved,
                     detail: "Sorted", path: home + "/Files/" + file,
                     destination: home + "/Files/Sorted/" + file, run: run)
    }

    /// Waits for a condition instead of a duration, and fails naming it: a
    /// sleep of a fixed length is a race with a deadline.
    private func until(_ what: String, _ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), what)
    }

    func testAPassTheEngineJustMadeAppearsWithoutAGesture() async {
        let wire = AutopilotWire()
        let model = model(on: wire)
        await model.firstLoad?.value
        XCTAssertEqual(model.history, [], "the history was not empty, so this proves nothing")
        await until("the model never subscribed to the engine's events") {
            wire.eventReaderCount > 0
        }

        wire.holds([record("a.pdf", run: "p1")])
        wire.announce(AutopilotEvent.history)

        await until("the pass the engine announced never reached the page") {
            !model.history.isEmpty
        }
        XCTAssertEqual(model.history.map(\.file), ["a.pdf"])
        XCTAssertEqual(model.runs.map(\.id), ["p1"],
                       "the passes were not regrouped, so the section draws the old ones")
    }

    /// The freshness channel lives in the view model, not in the page: pages
    /// unmount off screen (`helmIdlesOffScreen`) and remount on return, and a
    /// `.task` on the page re-read the history on every remount — the second
    /// read of the same store on open, and a re-read per wake after that. The
    /// page draws; the model hears.
    func testThePageItselfDoesNotReadTheHistory() throws {
        let file = try RepoSource.swiftFiles(under: "Sources/Modules/Autopilot/UI")
            .first { $0.hasSuffix("AutopilotSettingsPage.swift") }
        let source = try RepoSource.text(of: XCTUnwrap(file))
        XCTAssertFalse(source.contains("loadHistory"),
                       "the page reads the history itself again, which is the "
                       + "double read on open this test exists to keep out")
    }
}
