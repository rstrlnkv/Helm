import XCTest
@testable import HelmUI

/// A revision rather than a flag. A `Bool` makes "show the new tour once" and
/// "the flag got cleared by accident" the same state, and somebody has to
/// remember to clear it; a number that only moves when the tour is worth
/// showing again cannot be cleared by accident.
final class WelcomeGateTests: XCTestCase {
    func testAnInstallationThatHasSeenNothingIsShownTheTour() {
        XCTAssertTrue(WelcomeGate.shouldShow(seenRevision: 0))
    }

    func testAnInstallationThatHasSeenThisRevisionIsNotShownItAgain() {
        XCTAssertFalse(WelcomeGate.shouldShow(seenRevision: WelcomeGate.revision))
    }

    func testAFutureRevisionIsShownAgain() {
        XCTAssertTrue(WelcomeGate.shouldShow(seenRevision: WelcomeGate.revision - 1))
    }

    /// Someone who ran a later build and went back must not be shown a tour
    /// they have already seen a newer version of.
    func testARevisionFromTheFutureIsNotShown() {
        XCTAssertFalse(WelcomeGate.shouldShow(seenRevision: WelcomeGate.revision + 5))
    }
}
