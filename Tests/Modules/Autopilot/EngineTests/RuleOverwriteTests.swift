import Foundation
import XCTest
@testable import Module_Autopilot_Engine

/// Whether a new rule set may be written over the one that is stored. A rule
/// set the engine has refused to run must not be overwritten either: the screen
/// behind that refusal shows no folders, and the next ordinary gesture would
/// write an empty list over the person's work.
///
/// Exhaustive over `SettingSeal.Verdict`, so a fourth case is a build error
/// rather than a case this test forgot.
final class RuleOverwriteTests: XCTestCase {

    func testNothingStoredIsWrittenOver() {
        XCTAssertTrue(RuleSeal.mayOverwrite(nil))
    }

    func testHelmsOwnRulesAreWrittenOver() {
        XCTAssertTrue(RuleSeal.mayOverwrite(.sealed))
    }

    /// The upgrade: rules from before the seal are the person's own, and the
    /// run that adopts them may go on saving.
    func testRulesFromBeforeTheSealAreWrittenOver() {
        XCTAssertTrue(RuleSeal.mayOverwrite(.adopt))
    }

    func testARuleSetSomethingElseWroteIsNotWrittenOver() {
        XCTAssertFalse(RuleSeal.mayOverwrite(.broken))
    }
}
