import XCTest
import HelmContract
import HelmRuntime
import HelmUI
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The one order of events nobody draws: the answer that arrives after the
/// question was withdrawn.
///
/// `cancel()` stops the engine and puts the page back, but the request task is
/// still awaiting — and without the generation check whatever the transport
/// eventually returned was written straight into `groups`. A cancelled search
/// resurfaced as if it had been asked for; and with a second search already
/// running, the first one's corpse overwrote the newer folder's results.
///
/// The transport is hand-cranked: every "find" parks until the test releases
/// it, so the interleaving is chosen rather than raced. An assertion that
/// holds only for a lucky delay is not a test.
@MainActor
final class DuplicateSearchRaceTests: XCTestCase {

    /// A cancelled search's answer must not arrive as though it had been asked
    /// for. Cancel is a withdrawal, not a pause.
    func testALateAnswerToACancelledSearchIsDiscarded() async {
        let transport = HeldTransport()
        let dvm = heldModel(transport)
        dvm.search()
        await untilParked(transport, count: 1)
        XCTAssertEqual(dvm.phase, .searching)

        dvm.cancel()
        XCTAssertEqual(dvm.phase, .start)

        transport.release(0, folder: "withdrawn")
        for _ in 0..<20 { await Task.yield() }

        XCTAssertTrue(dvm.groups.isEmpty, "a withdrawn search wrote its answer anyway")
        XCTAssertEqual(dvm.phase, .start)
    }

    /// Two searches in flight: the older one finishing last must not overwrite
    /// the newer one's folder.
    func testTheOlderSearchCannotOverwriteTheNewer() async {
        let transport = HeldTransport()
        let dvm = heldModel(transport)
        dvm.search()
        await untilParked(transport, count: 1)
        dvm.cancel()
        dvm.search()
        await untilParked(transport, count: 2)
        XCTAssertEqual(transport.parkedCount, 2, "both requests should be in flight")

        // The newer one answers first, then the older one arrives late.
        transport.release(1, folder: "newer")
        for _ in 0..<20 { await Task.yield() }
        transport.release(0, folder: "older")
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(dvm.groups.count, 1)
        XCTAssertTrue(dvm.groups[0].paths.allSatisfy { $0.contains("newer") },
                      "the older search overwrote the newer: \(dvm.groups[0].paths)")
    }
}
