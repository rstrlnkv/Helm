import XCTest
@testable import Module_KeepAwake_Engine

/// What the top of the page says, and what it offers to do about it.
///
/// The page used to draw three metric cells — `OFF · — · 0` on a first run —
/// and no control at all: the one screen that reports the session was the one
/// screen that could not change it. Two of those three cells were figures the
/// house's own rule says must not be drawn when they cannot be read.
final class SessionHeroTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    func testNothingHoldingOffersTheWaysToStart() {
        XCTAssertEqual(SessionHero.of(isActive: false, endDate: nil, conditions: [], now: now),
                       .idle)
    }

    func testATimedSessionCountsDownAndCanBeExtendedOrStopped() {
        let end = now.addingTimeInterval(600)
        XCTAssertEqual(SessionHero.of(isActive: true, endDate: end,
                                      conditions: [.manual, .timer], now: now),
                       .timed(until: end))
    }

    /// Zero is this module's spelling of «until I say stop», and the hero has
    /// to say that rather than draw a countdown of nothing.
    func testASessionWithNoDeadlineSaysSoInsteadOfCountingDown() {
        XCTAssertEqual(SessionHero.of(isActive: true, endDate: nil,
                                      conditions: [.manual], now: now),
                       .indefinite)
    }

    /// Held by a rule and not by a person: the hero names the reasons rather
    /// than offering to extend a timer that does not exist.
    func testASessionHeldByRulesNamesThem() {
        XCTAssertEqual(SessionHero.of(isActive: true, endDate: nil,
                                      conditions: [.externalDisplay, .app], now: now),
                       .automatic([.externalDisplay, .app]))
    }

    /// A deadline that has already passed is not a countdown. The engine's own
    /// expiry may not have run yet — the clock is what the view has — and a
    /// hero drawing «-0:03» is the module reporting a session that ended.
    func testADeadlineInThePastIsNotATimedSession() {
        XCTAssertEqual(SessionHero.of(isActive: true, endDate: now.addingTimeInterval(-1),
                                      conditions: [.manual], now: now),
                       .indefinite)
    }

    /// Manual and timer are not reasons a person can be told about: they are
    /// the session itself. Only the automatic three are named.
    func testTheAutomaticStateIgnoresManualAndTimer() {
        XCTAssertEqual(SessionHero.of(isActive: true, endDate: nil,
                                      conditions: [.manual, .power], now: now),
                       .indefinite,
                       "a manual session stays manual even when a rule also holds")
    }
}
