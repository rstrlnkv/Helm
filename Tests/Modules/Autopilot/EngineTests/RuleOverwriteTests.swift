import Foundation
import XCTest
@testable import HelmRuntime
@testable import Module_Autopilot_Engine

/// Whether a new rule set may be written over the one that is stored.
///
/// `RuleSealTests` covers what the seal says about what is on disk. This covers
/// the one decision taken from that verdict on the way *out*: a rule set the
/// engine has just refused to run is also a rule set it must not overwrite,
/// because the screen behind that refusal shows no folders and the next
/// ordinary gesture writes an empty list over the person's work.
///
/// Exhaustive over `SettingSeal.Verdict` on purpose — the three cases are the
/// three states the plist can be in, and a fourth would be a build error rather
/// than a case this test forgot.
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
