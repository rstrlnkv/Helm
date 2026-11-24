import XCTest
@testable import Module_Duplicates_Engine

/// **A copy with no date stays: `KeepReason.undated`, a rung above `.date`.**
///
/// A `.date` rung silent where one date is missing is not an ordering, and
/// walk order would then pick the survivor
/// (`TheSurvivorDoesNotDependOnWalkOrderTests`). A rung is a claim about
/// somebody's files and a sentence in their language, which the permutation
/// test cannot see.
///
/// **The undated copy stays whatever is below the rung.** In `KeepPolicyTests`
/// the dateless copy is also the shallower one, so those cases ask
/// `SurvivingCopy.reason`; this file keeps the other half: a dateless copy with
/// every rung below it *against* it.
///
/// `TransitFolders(roots: [])` so the `.place` rung is silent for every path
/// here and nothing depends on where this Mac keeps Downloads.
final class ACopyWithNoDateIsTheOneThatStaysTests: XCTestCase {

    /// The copy with no date is four folders further in and sorts last, so every
    /// rung below the undated one is against it.
    private var copies: [FileFacts] {
        [facts("/Users/r/Archive/a.jpg", added: day(400)),
         facts("/Users/r/Archive/2019/Old/Deep/z.jpg")]
    }

    // MARK: - The rule

    /// **The copy nothing records the arrival of is the copy that stays**, and
    /// the module's act on the rest is to offer them for the Trash.
    func testTheUndatedCopyStaysEvenWhenEveryRungBelowIsAgainstIt() {
        for policy in KeepPolicy.allCases {
            XCTAssertEqual(SurvivingCopy.order(copies, by: rule(policy))[0].path,
                           "/Users/r/Archive/2019/Old/Deep/z.jpg", """
                policy «\(policy.rawValue)»: the deeper, later-sorting copy is the one whose \
                Date Added the filesystem never recorded, and the group kept the other one. \
                A blank date read as a loss is the rule `KeepPolicyTests` records being \
                put back — and read as silence it is the cycle \
                `TheSurvivorDoesNotDependOnWalkOrderTests` records.
                """)
        }
    }

    // MARK: - Controls

    /// **The control that keeps the rungs below.** Two copies that both lack a
    /// date are alike on this rung, so it says nothing and the ladder carries on
    /// to the shorter path.
    ///
    /// Without it the rule could be «the deeper copy wins» or «the second copy
    /// wins» and the test above would not notice.
    func testTwoCopiesWithoutDatesAreAlikeOnThisRung() {
        for policy in KeepPolicy.allCases {
            let ordered = SurvivingCopy.order([facts("/Users/r/Archive/2019/Old/deep.jpg"),
                                               facts("/Users/r/Archive/shallow.jpg")],
                                              by: rule(policy))
            XCTAssertEqual(ordered[0].path, "/Users/r/Archive/shallow.jpg",
                           "policy «\(policy.rawValue)»: neither has a date, so the missing "
                           + "date separates nothing and the depth rung answers")
            XCTAssertEqual(SurvivingCopy.reason(among: ordered, by: rule(policy)), .depth)
        }
    }

    /// **The control that keeps the date.** Two known dates are still the earlier
    /// copy's win: the undated rung sits above it rather than replacing it.
    func testTwoKnownDatesAreStillDecidedByTheDate() {
        for policy in KeepPolicy.allCases {
            let dated = [facts("/Users/r/Archive/a.jpg", added: day(400)),
                         facts("/Users/r/Archive/z.jpg", added: day(100))]
            XCTAssertEqual(SurvivingCopy.order(dated, by: rule(policy))[0].path,
                           "/Users/r/Archive/z.jpg")
            XCTAssertEqual(SurvivingCopy.reason(among: dated, by: rule(policy)), .date,
                           "policy «\(policy.rawValue)»: both dates are known, so the rung "
                           + "above them has nothing to say")
        }
    }
}
