import HelmRuntime
import XCTest

/// **Telling a reply from a superseded one, in the one place the rule is written
/// down.** Two view models had counted this out by hand — Duplicates, and then
/// Leftovers after two quick toggles were found handing `items` to the last
/// *completion* rather than the last request.
final class LatestRequestTests: XCTestCase {

    func testTheTokenJustTakenIsTheLatest() {
        var requests = LatestRequest()
        let mine = requests.take()

        XCTAssertTrue(requests.isLatest(mine))
    }

    func testAnEarlierTokenIsNotTheLatest() {
        var requests = LatestRequest()
        let older = requests.take()
        let newer = requests.take()

        XCTAssertFalse(requests.isLatest(older),
                       "an answer to a request the person has already replaced would land")
        XCTAssertTrue(requests.isLatest(newer))
    }

    /// Abandoning everything in flight is taking a token and dropping it —
    /// Duplicates' `cancel`, which has nothing to do with the token it takes.
    func testTakingAndDroppingATokenAbandonsWhatWasRunning() {
        var requests = LatestRequest()
        let running = requests.take()

        _ = requests.take()

        XCTAssertFalse(requests.isLatest(running))
    }

    /// Nothing has been asked for yet, so no token can be the latest — a zero
    /// standing for «the first request» is how an uninitialized token would pass.
    func testBeforeTheFirstRequestNothingIsLatest() {
        let requests = LatestRequest()

        XCTAssertFalse(requests.isLatest(0))
        XCTAssertFalse(requests.isLatest(1))
    }
}
