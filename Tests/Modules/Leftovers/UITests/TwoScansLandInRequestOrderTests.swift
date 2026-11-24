import XCTest
import HelmTestSupport
import Module_Leftovers_Engine
@testable import Module_Leftovers_UI

/// **Two scans in flight land in request order: the list goes to the last one
/// asked for, not the last one to finish.**
///
/// It is not only the Scan button that calls `scan()`: `setDisabled` rescans so
/// the row shows what launchd actually did, and `trash` rescans after a removal.
/// Two quick toggles are two scans in flight over the same `items`.
///
/// The fake below is a gate per request rather than one gate, because the state
/// this is about is *two* requests outstanding at once
/// (Architecture/TestsAndMeasurement.md § Fakes).
@MainActor
final class TwoScansLandInRequestOrderTests: XCTestCase {

    private final class OrderedScans: LeftoversWork, @unchecked Sendable {
        private let lock = NSLock()
        private let answers: [[StaleItem]]
        private let gates: [(stream: AsyncStream<Void>, continuation: AsyncStream<Void>.Continuation)]
        private var taken = 0
        /// A removal, answered at once — because the request this file is about is
        /// the **rescan `trash` makes afterwards**, and a fake that could only answer
        /// scans could not put a removal in the middle of two of them
        /// (`testAScanInFlightWhenARemovalLandsDoesNotWinTheList`).
        private let removal: LeftoversRemoval

        init(answers: [[StaleItem]],
             removal: LeftoversRemoval = LeftoversRemoval(removed: [], refused: [],
                                                          freedBytes: 0)) {
            self.answers = answers
            self.removal = removal
            gates = answers.map { _ in AsyncStream<Void>.makeStream() }
        }

        /// How many scans have reached the fake.
        var requests: Int { lock.withLock { taken } }

        /// This request's place in the queue. Synchronous, and the lock is taken
        /// and released inside it, so no lock is held across a suspension.
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

        func scan() async -> [StaleItem] {
            let mine = claim()
            // Suspends until this request in particular is answered. A
            // `return` here would make every ordering the same ordering.
            for await _ in gates[mine].stream {}
            return answers[mine]
        }

        func trash(_ paths: [String]) async -> LeftoversRemoval { removal }

        func setDisabled(_ request: LeftoversToggle) async {}
    }

    private func agent(_ name: String) -> StaleItem {
        StaleItem(path: "/tmp/\(name).plist", identifier: name, kind: .launchAgent,
                  sizeBytes: 4_096, status: .orphaned)
    }

    /// Both in flight, the newer answered first: the older reply must be dropped
    /// rather than land on top of it.
    func testAnOlderScansAnswerIsDropped() async {
        let work = OrderedScans(answers: [[agent("stale")], [agent("fresh")]])
        let model = LeftoversViewModel(work: work)

        let older = Task { await model.scan() }
        await waitUntil("scan 1 reaches the fake") { work.requests >= 1 }
        let newer = Task { await model.scan() }
        await waitUntil("scan 2 reaches the fake") { work.requests >= 2 }
        XCTAssertEqual(work.requests, 2, "precondition: two scans are in flight at once")

        work.answer(1)
        await newer.value
        XCTAssertEqual(model.items.map(\.identifier), ["fresh"],
                       "precondition: the newest answer reached the list")

        work.answer(0)
        await older.value

        XCTAssertEqual(model.items.map(\.identifier), ["fresh"],
                       "the list shows the answer to the request the person made first, "
                       + "because it is the one that finished last")
    }

    /// And the flag the Scan button reads belongs to the newest request: an older
    /// scan finishing must not report the page idle while a newer one is running.
    func testTheOlderScanFinishingDoesNotSayThePageIsIdle() async {
        let work = OrderedScans(answers: [[agent("stale")], [agent("fresh")]])
        let model = LeftoversViewModel(work: work)

        let older = Task { await model.scan() }
        await waitUntil("scan 1 reaches the fake") { work.requests >= 1 }
        let newer = Task { await model.scan() }
        await waitUntil("scan 2 reaches the fake") { work.requests >= 2 }

        work.answer(0)
        await older.value

        XCTAssertTrue(model.scanning,
                      "the page says it is done while a scan is still running, so the button "
                      + "invites a third one")

        work.answer(1)
        await newer.value
        XCTAssertFalse(model.scanning, "the flag outlived the work it describes")
    }

    // MARK: - And a removal in the middle of them

    /// **A scan already in flight when a removal finishes.** Three scans can be
    /// outstanding in one ordinary sequence: the one that built the list, one the
    /// person started while the batch was running, and the one the removal makes
    /// to show what happened.
    ///
    /// The removal's rescan is the newest request, so it must win, even when the
    /// person's older scan is answered last. If it lost, the page would show a list
    /// taken *before* the removal under a report saying what the removal did.
    ///
    /// It fails on a `LatestRequest` that latches instead of counting, on a `trash`
    /// that rescans before writing its report, and on any `items = found` without
    /// the token check.
    func testAScanInFlightWhenARemovalLandsDoesNotWinTheList() async {
        let before = agent("before-the-removal")
        let work = OrderedScans(answers: [[before], [before], [agent("after-the-removal")]],
                                    removal: LeftoversRemoval(removed: [before.path], refused: [],
                                                              freedBytes: 4_096))
        let model = LeftoversViewModel(work: work)

        // The scan that builds the list, answered.
        let first = Task { await model.scan() }
        await waitUntil("scan 1 reaches the fake") { work.requests >= 1 }
        work.answer(0)
        await first.value
        model.selected = Set(model.selectablePaths)
        XCTAssertEqual(model.selected.count, 1, "precondition: a row is ticked to remove")

        // The person presses Scan again — it reaches the fake and stays there.
        let theirs = Task { await model.scan() }
        await waitUntil("scan 2 reaches the fake") { work.requests >= 2 }
        XCTAssertEqual(work.requests, 2, "precondition: their scan is in flight")

        // And then the removal runs to completion, rescan and all.
        let removal = Task { await model.removeSelected() }
        await waitUntil("scan 3 reaches the fake") { work.requests >= 3 }
        XCTAssertEqual(work.requests, 3,
                       "precondition: the removal made its own rescan while theirs was still out")
        work.answer(2)
        await removal.value
        XCTAssertEqual(model.items.map(\.identifier), ["after-the-removal"],
                       "precondition: the removal's own rescan reached the list")

        // Their older scan comes back last, with the list as it was before the batch.
        work.answer(1)
        await theirs.value

        XCTAssertEqual(model.items.map(\.identifier), ["after-the-removal"], """
            the list is the one taken before the removal, under a report saying what the removal \
            did — so the page invites the person to tick rows it has already been told are gone.
            """)
        XCTAssertEqual(model.removedCount, 1, "and the report itself is still the removal's")
    }
}
