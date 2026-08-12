import XCTest
import HelmRuntime
@testable import Module_KeepAwake_Engine

/// The battery guard has everything stopped, and the rule rows said «Not
/// applying right now».
///
/// True, and the least useful of the three things that sentence could mean. The
/// veto is not a property of the rule — it is a property of the Mac: while the
/// charge is under the floor nothing this module does will run, whatever any
/// rule's trigger says. `RuleNote` had no input for it, so a rule whose trigger
/// was *still true* read exactly like one whose app had quit, on a page whose
/// banner two hundred points above was already saying why.
///
/// This is the same defect `.paused` was added for, one guard over: two accounts
/// of one rule on one screen, and the row's is the one that sounds like nothing
/// is wrong.
final class ARuleUnderTheBatteryVetoTests: XCTestCase {

    func testARuleUnderTheVetoSaysSoRatherThanSayingItDoesNotApply() {
        let note = RuleNote.of(enabled: true, satisfied: false, batteryStopped: true,
                               suppressed: false, triggerHolds: true)
        XCTAssertEqual(note, .vetoed,
                       "the row said «Not applying right now» while the reason it was not "
                       + "applying was the battery guard, named in a banner above it")
    }

    /// The veto is about the Mac, so a rule whose own trigger is false says it
    /// too — unlike `.paused`, which is about one rule having been silenced.
    func testTheVetoDoesNotAskWhetherTheRulesOwnTriggerHolds() {
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: false, batteryStopped: true,
                                   suppressed: false, triggerHolds: false), .vetoed)
    }

    /// It outranks the pause. Both can be true — a rule was stopped by hand and
    /// then the charge fell under the floor — and of the two only one explains
    /// why nothing at all is happening; «Resume» cannot do what it says while
    /// the guard is in force, which is why the banners are ordered this way too.
    func testTheVetoOutranksAPause() {
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: false, batteryStopped: true,
                                   suppressed: true, triggerHolds: true), .vetoed)
    }

    /// And a switched-off rule still explains what switching it on would do.
    /// What a rule *means* is not a fact about the charge.
    func testASwitchedOffRuleStillExplainsItself() {
        XCTAssertEqual(RuleNote.of(enabled: false, satisfied: false, batteryStopped: true,
                                   suppressed: false, triggerHolds: true), .meaning)
    }

    /// The control: with the guard idle every one of the four earlier cases is
    /// what it was.
    func testNothingElseMoved() {
        XCTAssertEqual(RuleNote.of(enabled: false, satisfied: false, batteryStopped: false,
                                   suppressed: false, triggerHolds: false), .meaning)
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: true, batteryStopped: false,
                                   suppressed: false, triggerHolds: true), .applies)
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: false, batteryStopped: false,
                                   suppressed: false, triggerHolds: false), .waiting)
        XCTAssertEqual(RuleNote.of(enabled: true, satisfied: false, batteryStopped: false,
                                   suppressed: true, triggerHolds: true), .paused)
    }
}
