import XCTest
import HelmTestSupport
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The one order of events nobody draws: the answer that arrives after the
/// question was withdrawn.
///
/// `cancel()` stops the engine and puts the page back, but the request task is
/// still awaiting; the generation check keeps whatever the work eventually
/// returns out of `groups`, so a cancelled search does not resurface and an
/// older search cannot overwrite a newer one's results.
///
/// The work is hand-cranked: every "find" parks until the test releases
/// it, so the interleaving is chosen rather than raced.
@MainActor
final class DuplicateSearchRaceTests: XCTestCase {

    /// A cancelled search's answer must not arrive as though it had been asked
    /// for. Cancel is a withdrawal, not a pause.
    func testALateAnswerToACancelledSearchIsDiscarded() async {
        let work = HeldWork()
        let dvm = heldModel(work)
        dvm.search()
        await waitUntil("1 search(es) parked on the work") { work.parkedCount >= 1 }
        XCTAssertEqual(dvm.phase, .searching)

        dvm.cancel()
        XCTAssertEqual(dvm.phase, .start)

        work.release(0, folder: "withdrawn")
        await grace()

        XCTAssertTrue(dvm.groups.isEmpty, "a withdrawn search wrote its answer anyway")
        XCTAssertEqual(dvm.phase, .start)
    }

    /// Two searches in flight: the older one finishing last must not overwrite
    /// the newer one's folder.
    func testTheOlderSearchCannotOverwriteTheNewer() async {
        let work = HeldWork()
        let dvm = heldModel(work)
        dvm.search()
        await waitUntil("1 search(es) parked on the work") { work.parkedCount >= 1 }
        dvm.cancel()
        dvm.search()
        await waitUntil("2 search(es) parked on the work") { work.parkedCount >= 2 }
        XCTAssertEqual(work.parkedCount, 2, "both requests should be in flight")

        // The newer one answers first, then the older one arrives late.
        work.release(1, folder: "newer")
        await waitUntil("the newer search landed") { !dvm.groups.isEmpty }
        work.release(0, folder: "older")
        await grace()

        XCTAssertEqual(dvm.groups.count, 1)
        XCTAssertTrue(dvm.groups[0].paths.allSatisfy { $0.contains("newer") },
                      "the older search overwrote the newer: \(dvm.groups[0].paths)")
    }
}
