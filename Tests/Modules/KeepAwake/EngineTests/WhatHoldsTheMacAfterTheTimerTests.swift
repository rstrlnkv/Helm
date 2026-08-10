import XCTest
@testable import Module_KeepAwake_Engine

/// The one question a countdown cannot answer about itself: what happens at
/// zero.
///
/// A rule that is met while the timer runs is met when it stops, so the session
/// carries on — and until this line existed the page showed a figure counting
/// down to nothing and let the person guess. The setting that ends automation
/// with the timer says the opposite, and it too was invisible while it acted.
final class WhatHoldsTheMacAfterTheTimerTests: XCTestCase {

    private func holder(_ conditions: Set<ActiveCondition>,
                        timerEndsAutomation: Bool = false) -> ActiveCondition? {
        SessionHero.holderAfterTimer(conditions: conditions,
                                     timerEndsAutomation: timerEndsAutomation)
    }

    func testARuleThatIsMetNowStillHoldsAfterwards() {
        XCTAssertEqual(holder([.timer, .externalDisplay]), .externalDisplay)
    }

    /// The setting acting, in the one place it can be seen acting.
    func testNothingHoldsWhenTheTimerEndsAutomationToo() {
        XCTAssertNil(holder([.timer, .externalDisplay], timerEndsAutomation: true))
    }

    /// Manual is not a rule. Nobody set a condition that could fire again, so
    /// there is nothing to promise about zero.
    func testAManualSessionPromisesNothing() {
        XCTAssertNil(holder([.manual, .timer]))
    }

    func testACountdownAloneHoldsNothingAfterwards() {
        XCTAssertNil(holder([.timer]))
    }

    /// A sentence names one reason. Which one is decided by the enum's own
    /// order rather than by a set's iteration, which differs between runs —
    /// the line would otherwise say «the display» on one launch and «the
    /// charger» on the next with nothing having changed.
    func testTheAnswerIsStableWhenSeveralRulesHold() {
        let all: Set<ActiveCondition> = [.timer, .app, .power, .externalDisplay]
        let answers = (0..<20).map { _ in holder(all) }
        XCTAssertEqual(Set(answers).count, 1, "the same state answered two ways")
        XCTAssertEqual(answers.first, .externalDisplay,
                       "the order is ActiveCondition's own, which the panel also draws")
    }
}
