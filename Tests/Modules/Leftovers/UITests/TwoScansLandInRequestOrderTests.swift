import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **Two scans could land out of order, and the list went to the last one to
/// finish.**
///
/// `scan()` had no latch of any kind, and it is not only the Scan button that
/// calls it: `setDisabled` rescans so the row shows what launchd actually did, and
/// `trash` rescans after a removal. Two quick toggles are therefore two scans in
/// flight over the same `items`, and whichever the machine happens to answer last
/// wins — the family CLAUDE.md names «last writer wins by scheduling», one module
/// over from Autopilot's tampered-rules verdict.
///
/// The fake below is a gate per request rather than one gate, because the state
/// this is about is *two* requests outstanding at once: a transport that could
/// only hold one open could not represent the moment the defect lives in
/// (CLAUDE.md § A fake simpler than the thing it stands for).
@MainActor
final class TwoScansLandInRequestOrderTests: XCTestCase {

    private final class OrderedScans: EngineTransport, @unchecked Sendable {
        var events: AsyncStream<EngineEvent> { AsyncStream { _ in } }
        private let lock = NSLock()
        private let answers: [[StaleItem]]
        private let gates: [(stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation)]
        private var taken = 0
        /// A removal, answered at once — because the request this file is about is
        /// the **rescan `trash` makes afterwards**, and that is a scan like any
        /// other. A fake that could only answer scans could not put a removal in
        /// the middle of two of them, which is the interleaving the survey named
        /// and `testAScanInFlightWhenARemovalLandsDoesNotWinTheList` is about.
        private let removal: LeftoversRemoval

        init(answers: [[StaleItem]],
             removal: LeftoversRemoval = LeftoversRemoval(removed: [], refused: [],
                                                          freedBytes: 0)) {
            self.answers = answers
            self.removal = removal
            gates = answers.map { _ in AsyncStream<Void>.makeStream() }
        }

        /// How many scans have reached the wire.
        var requests: Int { lock.withLock { taken } }

        /// This request's place in the queue. Synchronous, and the lock is taken
        /// and released inside it: Swift 6 refuses `NSLock.lock()` in an `async`
        /// function outright, which is the rule CLAUDE.md records
        /// `LocalTransport.setHandler` learning.
        private func claim() -> Int {
            lock.withLock {
                let mine = taken
                taken += 1
                return mine
            }
        }

        /// Answer the nth scan — the point of this fake: the second can be
        /// answered before the first.
        func answer(_ index: Int) { gates[index].continuation.finish() }

        func send(_ command: EngineCommand) async throws -> Data {
            switch LeftoversCommand(rawValue: command.name) {
            case .scan:
                let mine = claim()
                // Suspends until this request in particular is answered. A
                // `return` here would make every ordering the same ordering.
                for await _ in gates[mine].stream {}
                return (try? JSONEncoder().encode(answers[mine])) ?? Data()
            case .trash:
                return (try? JSONEncoder().encode(removal)) ?? Data()
            case .setDisabled, .none:
                return Data()
            }
        }
    }

    private func agent(_ name: String) -> StaleItem {
        StaleItem(path: "/tmp/\(name).plist", identifier: name, kind: .launchAgent,
                  sizeBytes: 4_096, status: .orphaned)
    }

    /// Both in flight, the newer answered first: the older reply must be dropped
    /// rather than land on top of it.
    func testAnOlderScansAnswerIsDropped() async {
        let transport = OrderedScans(answers: [[agent("stale")], [agent("fresh")]])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))

        let older = Task { await model.scan() }
        for _ in 0..<50 where transport.requests < 1 { await Task.yield() }
        let newer = Task { await model.scan() }
        for _ in 0..<50 where transport.requests < 2 { await Task.yield() }
        XCTAssertEqual(transport.requests, 2, "precondition: two scans are in flight at once")

        transport.answer(1)
        await newer.value
        XCTAssertEqual(model.items.map(\.identifier), ["fresh"],
                       "precondition: the newest answer reached the list")

        transport.answer(0)
        await older.value

        XCTAssertEqual(model.items.map(\.identifier), ["fresh"],
                       "the list shows the answer to the request the person made first, "
                       + "because it is the one that finished last")
    }

    /// And the flag the Scan button reads belongs to the newest request: an older
    /// scan finishing must not report the page idle while a newer one is running.
    func testTheOlderScanFinishingDoesNotSayThePageIsIdle() async {
        let transport = OrderedScans(answers: [[agent("stale")], [agent("fresh")]])
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))

        let older = Task { await model.scan() }
        for _ in 0..<50 where transport.requests < 1 { await Task.yield() }
        let newer = Task { await model.scan() }
        for _ in 0..<50 where transport.requests < 2 { await Task.yield() }

        transport.answer(0)
        await older.value

        XCTAssertTrue(model.scanning,
                      "the page says it is done while a scan is still running, so the button "
                      + "invites a third one")

        transport.answer(1)
        await newer.value
        XCTAssertFalse(model.scanning, "the flag outlived the work it describes")
    }

    // MARK: - And a removal in the middle of them

    /// **The interleaving the survey named: a scan already in flight when a removal
    /// finishes.** The Scan button is `.disabled(lvm.scanning)` and nothing more, so
    /// it is live all the way through a removal — and `trash` ends with a rescan of
    /// its own. Three scans are therefore outstanding in one ordinary sequence: the
    /// one that built the list, the one the person started while the batch was
    /// running, and the one the removal makes to show what happened.
    ///
    /// The removal's rescan is the newest request, so it must win — even when the
    /// person's older scan is the last to be answered. If it loses, the page shows a
    /// list taken *before* the removal directly under a report saying what the
    /// removal did, which is the one pairing this screen must not draw: rows the
    /// person is invited to tick again, in a list the report has already contradicted.
    ///
    /// Nothing here needs a fix today — this is the ground walked, pinned. It can
    /// fail: it fails on a `LatestRequest` that latches instead of counting, on a
    /// `trash` that rescans before writing its report, and on any return to `items =
    /// found` without the token check.
    func testAScanInFlightWhenARemovalLandsDoesNotWinTheList() async {
        let before = agent("before-the-removal")
        let transport = OrderedScans(answers: [[before], [before], [agent("after-the-removal")]],
                                    removal: LeftoversRemoval(removed: [before.path], refused: [],
                                                              freedBytes: 4_096))
        let model = LeftoversViewModel(vm: ModuleViewModel(transport: transport))

        // The scan that builds the list, answered.
        let first = Task { await model.scan() }
        for _ in 0..<50 where transport.requests < 1 { await Task.yield() }
        transport.answer(0)
        await first.value
        model.selected = Set(model.selectablePaths)
        XCTAssertEqual(model.selected.count, 1, "precondition: a row is ticked to remove")

        // The person presses Scan again — it reaches the wire and stays there.
        let theirs = Task { await model.scan() }
        for _ in 0..<50 where transport.requests < 2 { await Task.yield() }
        XCTAssertEqual(transport.requests, 2, "precondition: their scan is in flight")

        // And then the removal runs to completion, rescan and all.
        let removal = Task { await model.removeSelected() }
        for _ in 0..<200 where transport.requests < 3 { await Task.yield() }
        XCTAssertEqual(transport.requests, 3,
                       "precondition: the removal made its own rescan while theirs was still out")
        transport.answer(2)
        await removal.value
        XCTAssertEqual(model.items.map(\.identifier), ["after-the-removal"],
                       "precondition: the removal's own rescan reached the list")

        // Their older scan comes back last, with the list as it was before the batch.
        transport.answer(1)
        await theirs.value

        XCTAssertEqual(model.items.map(\.identifier), ["after-the-removal"], """
            the list is the one taken before the removal, under a report saying what the removal \
            did — so the page invites the person to tick rows it has already been told are gone.
            """)
        XCTAssertEqual(model.removedCount, 1, "and the report itself is still the removal's")
    }
}
