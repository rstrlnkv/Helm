import Foundation
import HelmRuntime
import HelmTestSupport
import XCTest
@testable import Module_Duplicates_Engine

/// The heaviest read in the module obeys Stop between files.
///
/// `trash` verifies every pair before anything moves — minutes on an
/// external drive — and it used to do that un-abandonably: `cancel` reached only the
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

    private func plans(_ count: Int) throws -> [DuplicatePlan] {
        let keep = try write("keep.bin", "the same bytes")
        return try (0..<count).map {
            DuplicatePlan(remove: try write("copy\($0).bin", "the same bytes"), keep: keep)
        }
    }

    private func stopRemoval(of engine: DuplicatesEngine) {
        engine.stopRemoval()
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

        stopRemoval(of: engine)
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
                                      trashing: neverTrashes,
                                      verifying: { { parked.check($0, $1) } })
        var plans = try plans(2)
        plans.append(DuplicatePlan(remove: "/System/Library/nope.bin",
                                   keep: plans[0].keep))

        let removal = Task { await engine.trash(plans) }
        for _ in 0..<20_000 where parked.calls < 1 { await Task.yield() }
        XCTAssertEqual(parked.calls, 1)

        stopRemoval(of: engine)
        parked.release(2)
        let result = await removal.value

        XCTAssertTrue(result.cancelled)
        XCTAssertEqual(result.refused.map(\.reason), [.outOfScope])
        XCTAssertEqual(result.refused.map(\.path), ["/System/Library/nope.bin"])
    }

    /// Stop with no removal running is a no-op, not a crash and not a stop
    /// stored up for the next press.
    func testStopWithNothingRunningStopsNothingLater() async throws {
        let engine = DuplicatesEngine(settings: suiteSealGuard(), trashing: { try FileManager.default.removeItem(at: $0) })
        stopRemoval(of: engine)

        let plans = try plans(1)
        let result = await engine.trash(plans)

        XCTAssertFalse(result.cancelled,
                       "a stop pressed before the removal cancelled the removal after it")
        XCTAssertEqual(result.removed.count, 1)
    }
}
