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

/// `nil` used to fold together the two answers that differ most.
///
/// «Nothing is holding this Mac, so it goes to sleep» and «a rule is holding it
/// and this timer is about to pause that rule» were the same `nil`, so the
/// settings page could say nothing about the second — and the second is the
/// whole point of «A timer pauses the rule too». With that switch on, the one
/// state where the setting decides anything was the one state the page was
/// silent in: the note degenerated to «Timer until 16:03» and stopped.
final class WhatTheTimerEndsTests: XCTestCase {

    func testARuleGoesOnHoldingWhenTheTimerDoesNotEndAutomation() {
        XCTAssertEqual(SessionHero.afterTimer(conditions: [.externalDisplay],
                                              timerEndsAutomation: false),
                       .heldBy(.externalDisplay))
    }

    /// The case that had no way to be said.
    func testTheRuleIsPausedWhenTheTimerEndsAutomation() {
        XCTAssertEqual(SessionHero.afterTimer(conditions: [.externalDisplay],
                                              timerEndsAutomation: true),
                       .rulePaused,
                       "«the rule will be paused» and «nothing applies» were the same answer, "
                       + "so the page could not tell them apart and said neither")
    }

    /// …and with no rule at all it is still nothing, whatever the switch says —
    /// otherwise the setting would put a sentence about pausing a rule under a
    /// timer that is not pausing anything.
    func testNoRuleIsNothingEvenWithTheSwitchOn() {
        XCTAssertEqual(SessionHero.afterTimer(conditions: [.manual, .timer],
                                              timerEndsAutomation: true),
                       .nothing)
        XCTAssertEqual(SessionHero.afterTimer(conditions: [], timerEndsAutomation: false),
                       .nothing)
    }

    /// The older accessor still answers for the callers that only want «and
    /// then what holds it», and it must not start claiming a holder in the
    /// state it cannot describe.
    func testTheOlderAccessorStillAnswersNilForBothSilentCases() {
        XCTAssertNil(SessionHero.holderAfterTimer(conditions: [.externalDisplay],
                                                  timerEndsAutomation: true))
        XCTAssertNil(SessionHero.holderAfterTimer(conditions: [], timerEndsAutomation: false))
        XCTAssertEqual(SessionHero.holderAfterTimer(conditions: [.power],
                                                    timerEndsAutomation: false), .power)
    }
}
