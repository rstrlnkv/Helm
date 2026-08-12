import XCTest
@testable import Module_KeepAwake_Engine

/// The lid row had two notes and four states.
///
/// It said «Sleep is off …» while the lid was holding and what the grant costs
/// the rest of the time — a ternary in the page's body. Two of the four states
/// it can actually be in had nowhere to land:
///
/// - **macOS refused.** `reallyEngage` reads `setDisableSleep(true)` and can be
///   told no: the NOPASSWD rule can have been removed or edited by an admin, by
///   a migration, by somebody tidying `/etc/sudoers.d`. The engine logs it, sets
///   `active` false, and the row then drew the standing explanation of what the
///   password buys — as if nothing had been attempted. That is a lid somebody
///   was told they could close.
/// - **The rule is still there.** Switching the option off takes the grant back
///   out, and `removeSudoers` can be declined. Its `Bool` was discarded, so the
///   only account of a rule that outlived its feature was a log line that blamed
///   somebody else for writing it.
///
/// Out here as a case rather than a ternary for the reason `RuleNote` is: the fix
/// inside a `@ViewBuilder` would be the same four lines with nothing able to pin
/// them.
final class TheLidRowHasFourThingsToSayTests: XCTestCase {

    func testARefusalIsSaidRatherThanExplainingThePasswordAgain() {
        XCTAssertEqual(LidRowNote.of(refused: true, grantRemains: false, holding: false),
                       .refused,
                       "macOS refused to turn sleep off and the row went on describing what "
                       + "the password would buy")
    }

    /// The refusal outranks everything, because it is the one state in which the
    /// switch says one thing and the machine does another.
    func testARefusalOutranksTheRest() {
        XCTAssertEqual(LidRowNote.of(refused: true, grantRemains: true, holding: true), .refused)
    }

    func testSleepBeingOffIsStillTheLiveNote() {
        XCTAssertEqual(LidRowNote.of(refused: false, grantRemains: false, holding: true),
                       .sleepIsOff)
    }

    /// A rule left behind after the option went off. It cannot coexist with
    /// `holding` — the grant is only removed once the setting is false — and the
    /// order is stated anyway rather than left to the order of two `if`s.
    func testAGrantThatSurvivedItsFeatureIsSaid() {
        XCTAssertEqual(LidRowNote.of(refused: false, grantRemains: true, holding: false),
                       .grantRemains)
    }

    func testWithNothingWrongTheRowSaysWhatTheGrantCosts() {
        XCTAssertEqual(LidRowNote.of(refused: false, grantRemains: false, holding: false),
                       .whatItCosts)
    }
}
