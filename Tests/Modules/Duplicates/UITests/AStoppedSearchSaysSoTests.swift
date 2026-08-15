import HelmTestSupport
import XCTest
@testable import Module_Duplicates_UI

/// A cancelled search is a named outcome, not a return to «Pick a folder».
///
/// `cancel()` landed on `phase = .start` with the folder still chosen, so the
/// screen read exactly as it does before anything has happened — nothing said
/// the search was stopped, which is the removal's own defect one act over. The
/// removal got `removalStopped`; this is the same repair for the search.
@MainActor
final class AStoppedSearchSaysSoTests: XCTestCase {

    func testCancellingARunningSearchIsANamedOutcome() async {
        let transport = HeldTransport()
        let dvm = heldModel(transport)
        dvm.search()
        await untilParked(transport, count: 1)
        XCTAssertEqual(dvm.phase, .searching, "the search never started — this is about nothing")

        dvm.cancel()

        XCTAssertEqual(dvm.phase, .start)
        XCTAssertTrue(dvm.searchStopped,
                      "the stop left the start screen reading as if nothing had happened")
    }

    /// A search the engine gave up on — a nil reply is a cancellation on its
    /// side, or an engine that has gone — says so the same way: either way the
    /// folder was not read to the end and the person was told nothing.
    func testASearchTheEngineAbandonedSaysSoToo() async {
        let dvm = duplicatesModel(over: DuplicatesWire(groups: [], answering: .nothing))
        dvm.search()
        await settle()

        XCTAssertEqual(dvm.phase, .start)
        XCTAssertTrue(dvm.searchStopped)
    }

    /// The outcome belongs to the stopped search: the next press withdraws it,
    /// on the way in — a sentence about the previous search must not sit over a
    /// bar for the new one.
    func testTheNextSearchWithdrawsTheOutcome() async {
        let transport = HeldTransport()
        let dvm = heldModel(transport)
        dvm.search()
        await untilParked(transport, count: 1)
        dvm.cancel()
        XCTAssertTrue(dvm.searchStopped, "the stop never registered — this is about nothing")

        dvm.search()

        XCTAssertFalse(dvm.searchStopped)
    }

    /// The start screen says it. Read from the page's source the way
    /// `TheGroupHeaderKeepsItsButtonsTests` reads the header: the flag with no
    /// sentence drawn from it is a channel nobody listens to.
    func testTheStartScreenDrawsTheStoppedSentence() throws {
        let page = try RepoSource.text(of:
            "Sources/Modules/Duplicates/UI/DuplicatesSettingsPage.swift")
        XCTAssertTrue(page.contains("searchStopped ? DupStr.searchStopped() : DupStr.startHint"),
                      "the start screen no longer says a stopped search was stopped")
    }
}
