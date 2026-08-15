import Foundation
import HelmContract
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The heaviest read in the module names itself while it runs, reports how far
/// it has got, and obeys Stop between files.
///
/// `trash` re-reads every pair in full before anything moves — minutes on an
/// external drive — and it used to do that namelessly, silently and
/// un-abandonably: no phase, no progress event, and `cancel` reached only the
/// search. The verification port here parks on purpose: a check that answers
/// on the spot is over before Stop can be pressed, so every assertion about
/// "while it runs" would pass with the guard deleted.
final class ARemovalCanBeWatchedAndStoppedTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Under the home, because `UserFileScope` refuses everything else and
        // the scope gate runs before the verification.
        directory = scratchDirectory("watched-removal")
    }

    @discardableResult
    private func write(_ name: String, _ contents: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url.path
    }

    /// A verification mid-read: each call announces itself and then waits for
    /// the test, so the interleaving is chosen rather than raced.
    private final class ParkedVerify: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        private let gate = DispatchSemaphore(value: 0)

        var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
        func release(_ n: Int) { for _ in 0..<n { gate.signal() } }

        func check(_ remove: String, _ keep: String) -> DuplicateVerification.Verdict {
            lock.lock(); count += 1; lock.unlock()
            gate.wait()
            return .identical
        }
    }

    /// What the engine was told to trash — nothing, if Stop worked.
    private final class TrashRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
        func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    }

    private func plans(_ count: Int) throws -> [DuplicatePlan] {
        let keep = try write("keep.bin", "the same bytes")
        return try (0..<count).map {
            DuplicatePlan(remove: try write("copy\($0).bin", "the same bytes"), keep: keep)
        }
    }

    private func stopRemoval(of engine: DuplicatesEngine) async throws {
        _ = try await engine.transport.send(
            EngineCommand(name: DuplicatesCommand.stopRemoval.rawValue, payload: Data()))
    }

    func testStopBetweenFilesIsANamedOutcomeAndNothingMoves() async throws {
        let parked = ParkedVerify()
        let recorder = TrashRecorder()
        let engine = DuplicatesEngine(settings: suiteSealGuard(),
                                      trashing: { recorder.add($0) },
                                      verifying: { { parked.check($0, $1) } })
        let plans = try plans(3)

        let removal = Task { await engine.trash(plans) }
        // The subject first: the verification really began.
        for _ in 0..<20_000 where parked.calls < 1 { await Task.yield() }
        XCTAssertEqual(parked.calls, 1, "the removal never reached its first pair")

        try await stopRemoval(of: engine)
        // Every pair could go through from here — so a loop that ignores the
        // stop finishes all three instead of hanging, and the count below
        // catches it.
        parked.release(3)
        let result = await removal.value

        XCTAssertTrue(result.cancelled, "a stopped removal did not say so")
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(recorder.count, 0, "Stop was pressed and files moved anyway")
        XCTAssertEqual(parked.calls, 1,
                       "the loop went on verifying after the person said stop")
    }

    /// What was already known when Stop landed is still reported: a refusal is
    /// never silently discarded, stopped or not.
    func testAStoppedReplyKeepsTheRefusalsItAlreadyKnew() async throws {
        let parked = ParkedVerify()
        let engine = DuplicatesEngine(settings: suiteSealGuard(),
                                      trashing: { _ in },
                                      verifying: { { parked.check($0, $1) } })
        var plans = try plans(2)
        plans.append(DuplicatePlan(remove: "/System/Library/nope.bin",
                                   keep: plans[0].keep))

        let removal = Task { await engine.trash(plans) }
        for _ in 0..<20_000 where parked.calls < 1 { await Task.yield() }
        XCTAssertEqual(parked.calls, 1)

        try await stopRemoval(of: engine)
        parked.release(2)
        let result = await removal.value

        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.refused.map(\.reason), [.outOfScope])
        XCTAssertEqual(result.refused.map(\.path), ["/System/Library/nope.bin"])
    }

    /// The phase is open while the verification runs — named while it runs, not
    /// only after — and closed once the removal has answered.
    func testTheVerificationNamesItsPhaseWhileItRuns() async throws {
        let parked = ParkedVerify()
        let engine = DuplicatesEngine(settings: suiteSealGuard(),
                                      trashing: { _ in },
                                      verifying: { { parked.check($0, $1) } })
        let plans = try plans(1)

        let removal = Task { await engine.trash(plans) }
        for _ in 0..<20_000 where parked.calls < 1 { await Task.yield() }
        XCTAssertEqual(parked.calls, 1)

        XCTAssertTrue(HelmActivity.running.contains { $0.label == "duplicates.verify" },
                      "the heaviest read in the module runs namelessly")

        parked.release(1)
        _ = await removal.value
        XCTAssertFalse(HelmActivity.running.contains { $0.label == "duplicates.verify" },
                       "the phase outlived the removal it names")
    }

    /// Every verified pair is a tick a page can draw. The events are collected
    /// off the engine's own transport — the wire the page really listens to.
    func testEveryVerifiedPairCrossesTheWireAsProgress() async throws {
        let engine = DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
        let plans = try plans(2)

        let collector = ProgressCollector()
        let events = engine.transport.events
        let listening = Task {
            for await event in events where DuplicatesEvent(rawValue: event.name) == .progress {
                guard let tick = try? JSONDecoder().decode(DuplicateProgress.self,
                                                           from: event.payload)
                else { continue }
                collector.add(tick)
                if collector.ticks.count >= 2 { break }
            }
        }

        let result = await engine.trash(plans)
        for _ in 0..<20_000 where collector.ticks.count < 2 { await Task.yield() }
        listening.cancel()

        XCTAssertFalse(result.cancelled)
        XCTAssertEqual(result.removed.count, 2)
        XCTAssertEqual(collector.ticks.map(\.hashed), [1, 2],
                       "the page cannot draw how far a removal has got")
        XCTAssertEqual(Set(collector.ticks.map(\.candidates)), [2])
    }

    /// Stop with no removal running is a no-op, not a crash and not a stop
    /// stored up for the next press.
    func testStopWithNothingRunningStopsNothingLater() async throws {
        let engine = DuplicatesEngine(settings: suiteSealGuard(), trashing: { _ in })
        try await stopRemoval(of: engine)

        let plans = try plans(1)
        let result = await engine.trash(plans)

        XCTAssertFalse(result.cancelled,
                       "a stop pressed before the removal cancelled the removal after it")
        XCTAssertEqual(result.removed.count, 1)
    }

    private final class ProgressCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var collected: [DuplicateProgress] = []
        var ticks: [DuplicateProgress] { lock.lock(); defer { lock.unlock() }; return collected }
        func add(_ tick: DuplicateProgress) { lock.lock(); collected.append(tick); lock.unlock() }
    }
}
