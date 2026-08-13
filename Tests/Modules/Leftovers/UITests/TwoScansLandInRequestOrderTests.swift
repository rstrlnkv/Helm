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

        init(answers: [[StaleItem]]) {
            self.answers = answers
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
            case .trash, .setDisabled, .none:
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
}
