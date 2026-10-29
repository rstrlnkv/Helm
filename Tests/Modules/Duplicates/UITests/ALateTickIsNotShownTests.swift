import HelmRuntime
import HelmTestSupport
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// A tick that arrives after the search it belongs to was cancelled does not
/// reach the bar, nor one from an older search onto a newer one.
///
/// The fakes of this target report their ticks before they park, so none of them
/// can deliver one late; this work holds the search and reports a tick only when
/// the test lets it, which is the order a real walk can take when the engine's
/// cancel lands between two hashes.
@MainActor
final class ALateTickIsNotShownTests: XCTestCase {

    /// Parks `find`, then reports one tick and answers nil (a cancelled search).
    private final class LateTickWork: DuplicatesWork, @unchecked Sendable {
        private let lock = NSLock()
        private var gate: CheckedContinuation<Void, Never>?
        var parked: Bool { lock.withLock { gate != nil } }

        func find(under path: String, keeping policy: KeepPolicy,
                  progress: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateFindings? {
            await withCheckedContinuation { c in lock.withLock { gate = c } }
            progress?(DuplicateProgress(candidates: 9, hashed: 4))
            return nil
        }
        func release() {
            let c = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { gate = nil }
                return gate
            }
            c?.resume()
        }
        func cancel() {}
        func trash(_ plans: [DuplicatePlan], staying: [String],
                   progress: (@Sendable (DuplicateProgress) -> Void)?) async -> DuplicateRemoval {
            DuplicateRemoval(removed: [], refused: [], freedBytes: 0)
        }
        func stopRemoval() {}
        func backgroundScan() async -> ScanReport? { nil }
    }

    func testATickAfterCancelDoesNotReachTheStartScreen() async {
        let work = LateTickWork()
        let dvm = duplicatesModel(over: work)
        dvm.search()
        for _ in 0..<1000 where !work.parked { await Task.yield() }
        XCTAssertTrue(work.parked, "precondition: the search is in flight")

        dvm.cancel()
        work.release()
        await settle()

        XCTAssertEqual(dvm.phase, .start)
        XCTAssertNil(dvm.progress, "a late tick of a cancelled search is on the start screen")
    }

    func testATickAfterTheNextSearchStartedIsNotTheNextSearchsTick() async {
        let work = LateTickWork()
        let dvm = duplicatesModel(over: work)
        dvm.search()
        for _ in 0..<1000 where !work.parked { await Task.yield() }
        dvm.cancel()
        dvm.search()
        work.release()
        await settle()

        XCTAssertNil(dvm.progress, "the older search's tick landed on the newer search")
    }
}
