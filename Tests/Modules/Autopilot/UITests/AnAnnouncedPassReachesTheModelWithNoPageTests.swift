import XCTest
import HelmTestSupport
import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The engine says a pass went into the history while no page is open, and the
/// model, which now outlives the page, is the one that hears it.
///
/// An unattended sweep (the hourly timer, a file arriving) writes the history with
/// nobody looking. The model re-asks once a page has opened it, so the history it
/// holds is the engine's when the person comes back; before any page opened it,
/// the first `appear()` reads everything and a ping is not a reason to read the
/// rule store early. No view is built anywhere in this class. Defect class kept: an
/// announced pass is lost without a page, or read in without anyone having asked.
@MainActor
final class AnAnnouncedPassReachesTheModelWithNoPageTests: XCTestCase {

    private let home = "/Users/x"

    private func record(_ id: String) -> ActionRecord {
        ActionRecord(at: Date(), rule: "sort", file: id + ".pdf", kind: .moved, detail: "",
                     path: home + "/Downloads/" + id + ".pdf",
                     destination: home + "/Downloads/PDF/" + id + ".pdf", run: "run-" + id,
                     ruleID: "r", device: 1, inode: 1)
    }

    private func model(_ work: FakeAutopilotWork, _ changes: AsyncStream<Void>) -> AutopilotViewModel {
        AutopilotViewModel(work: work, historyChanges: changes,
                           presetFolders: FakePresetFolders([:]), home: home)
    }

    /// The stream as the descriptor makes it (`makeModule`): one slot, newest kept.
    /// The descriptor's own, so its buffering is what is under test.
    private func slot() -> (AsyncStream<Void>, AsyncStream<Void>.Continuation) {
        AutopilotDescriptor.historyChannel()
    }

    private func settle() async {
        for _ in 0..<100 { await Task.yield() }
        await grace()
    }

    /// Total failure (a loop that reads nothing) prints `history.count 0` against 1.
    func testAPassAnnouncedAfterThePageOpenedOnceIsReadIn() async {
        let (changes, changed) = slot()
        let work = FakeAutopilotWork()
        let rvm = model(work, changes)
        await rvm.appear()
        XCTAssertEqual(rvm.history.count, 0, "precondition: nothing yet in the history")

        work.holdsHistory([record("a")])
        changed.yield()

        await waitUntil("the announced pass is in the model, with no page built") {
            rvm.history.count == 1 && rvm.runs.count == 1
        }
        XCTAssertEqual(rvm.runs.first?.records.map(\.file), ["a.pdf"])
    }

    func testAPassAnnouncedBeforeAnyPageOpenedIsNotRead() async {
        let (changes, changed) = slot()
        let work = FakeAutopilotWork(history: [record("a")])
        let rvm = model(work, changes)

        changed.yield()
        await settle()
        XCTAssertEqual(work.calls, [], "a ping before any page opened read the engine")
        XCTAssertTrue(rvm.history.isEmpty)

        // Control: the same ping is read once a page has opened; and appear() has
        // read what the ping would have, so nothing was lost by not reading early.
        await rvm.appear()
        XCTAssertEqual(rvm.history.count, 1, "control: appear() did not read the history the ping announced")
        let reads = work.count("readHistory")
        changed.yield()
        await waitUntil("control: a ping after appear() is read") { work.count("readHistory") > reads }
    }

    /// The descriptor's one-slot stream is `bufferingNewest(1)`. After `appear()` the model's
    /// loop is already parked in `for await`, so the first ping goes straight to it and one
    /// more waits in the slot: three pings are at most two reads, never three. An `.unbounded`
    /// stream in `AutopilotDescriptor.historyChannel()` reads three.
    func testThreePingsBeforeAnyoneLooksAreAtMostTwoReads() async {
        let (changes, changed) = slot()
        let work = FakeAutopilotWork()
        let rvm = model(work, changes)
        await rvm.appear()
        let reads = work.count("readHistory")

        // All before the model's task can run: the main actor is held by this test
        // until the next suspension.
        changed.yield()
        changed.yield()
        changed.yield()
        await waitUntil("a ping is read") { work.count("readHistory") > reads }
        await settle()
        let extra = work.count("readHistory") - reads
        XCTAssertGreaterThanOrEqual(extra, 1, "the pings were never read")
        XCTAssertLessThanOrEqual(extra, 2,
                       "three pings before the task ran were read as \(extra) reads, one per ping")
    }
}
