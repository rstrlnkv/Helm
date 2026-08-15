import Foundation
import HelmContract
import HelmRuntime
import XCTest
@testable import Module_Duplicates_Engine

/// The verification's three verdicts reach the reply as three facts, not two.
///
/// `trash` folded `.unreadable` into the same refusal as `.changed`, so a pair
/// the engine could not read — a permission withdrawn, a volume gone, the
/// *survivor* unreadable — came back as `changedSinceScan`: «this is not where
/// Helm found it», said about a file that is exactly there. The verdict's own
/// doc keeps the two apart («not a licence to delete»); the reply has to.
final class AnUnreadablePairIsItsOwnRefusalTests: XCTestCase {

    private func engine(verdict: DuplicateVerification.Verdict,
                        trashing: @escaping @Sendable (URL) throws -> Void = { _ in
                            XCTFail("a pair that was not verified identical was moved")
                        }) -> DuplicatesEngine {
        DuplicatesEngine(settings: suiteSealGuard(),
                         trashing: trashing,
                         verifying: { { _, _ in verdict } })
    }

    /// The paths need only pass the scope gate — the verification is the port
    /// above, so nothing here reads the disk and nothing can be moved.
    private var plan: DuplicatePlan {
        DuplicatePlan(remove: "\(NSHomeDirectory())/Downloads/copy.bin",
                      keep: "\(NSHomeDirectory())/Downloads/keep.bin")
    }

    func testAnUnreadablePairIsRefusedAsUnreadableAndNothingMoves() async {
        let result = await engine(verdict: .unreadable).trash([plan])

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.refused.map(\.reason), [.unreadable],
                       "a pair the engine could not read was blamed for moving")
    }

    /// The split must not steal the other case: a pair that *did* change keeps
    /// the sentence written for it.
    func testAChangedPairStillSaysChangedSinceScan() async {
        let result = await engine(verdict: .changed).trash([plan])

        XCTAssertTrue(result.removed.isEmpty)
        XCTAssertEqual(result.refused.map(\.reason), [.changedSinceScan])
    }

    /// And a stopped removal reports the unreadable pair the same way — a
    /// refusal is never silently discarded, stopped or not. The verification
    /// parks so the stop lands *between* the two files, not after the reply:
    /// a check that answers on the spot is over before Stop can be pressed.
    func testAStoppedRemovalStillReportsTheUnreadablePairAsUnreadable() async throws {
        let parked = ParkedVerify(answering: .unreadable)
        let engine = DuplicatesEngine(settings: suiteSealGuard(),
                                      trashing: { _ in XCTFail("nothing may move") },
                                      verifying: { { parked.check($0, $1) } })
        let home = NSHomeDirectory()
        let plans = [DuplicatePlan(remove: "\(home)/Downloads/copy0.bin",
                                   keep: "\(home)/Downloads/keep.bin"),
                     DuplicatePlan(remove: "\(home)/Downloads/copy1.bin",
                                   keep: "\(home)/Downloads/keep.bin")]

        let removal = Task { await engine.trash(plans) }
        // The first pair is being read; stop, then let it finish its read.
        for _ in 0..<100_000 where parked.calls < 1 { await Task.yield() }
        XCTAssertEqual(parked.calls, 1, "the verification was never reached")
        _ = try await engine.transport.send(
            EngineCommand(name: DuplicatesCommand.stopRemoval.rawValue, payload: Data()))
        parked.release(1)
        let result = await removal.value

        XCTAssertTrue(result.cancelled, "the stop never landed — this test is about nothing")
        XCTAssertEqual(result.refused.map(\.reason), [.unreadable],
                       "the stopped path dropped or renamed the unreadable refusal")
    }
}
