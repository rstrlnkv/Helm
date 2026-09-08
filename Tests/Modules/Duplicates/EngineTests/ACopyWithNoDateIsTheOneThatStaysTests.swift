import XCTest
@testable import Module_Duplicates_Engine

/// **What the repair for the walk-order cycle decided, said out loud.**
///
/// `TheSurvivorDoesNotDependOnWalkOrderTests` holds the defect: `.date`
/// separated two known dates and was silent where one was missing, which is not
/// an ordering, so three copies with one dateless among them kept whichever copy
/// the walk handed over first. The repair is `KeepReason.undated`, a rung above
/// the date it is missing from — and a rung is a claim about somebody's files
/// and a sentence in their language, neither of which the permutation test can
/// see.
///
/// Two things it fixes in place. **The undated copy stays whatever is below the
/// rung**, which the fixtures already in the suite could not show: in
/// `SurvivingCopyTests` and `KeepPolicyTests` the dateless copy is also the
/// shallower one, so both were green whether the undated rung decided or the
/// depth rung did — they ask `SurvivingCopy.reason` now, which tells the two
/// apart on the fixture they already had. This file keeps the other half: a
/// dateless copy with every rung below it *against* it. And **the reason is the
/// rung that decided**, which is what stops the header saying «arrived first»
/// about a copy nothing on this Mac records the arrival of.
///
/// `TransitFolders(roots: [])` so the `.place` rung is silent for every path
/// here and nothing depends on where this Mac keeps Downloads.
final class ACopyWithNoDateIsTheOneThatStaysTests: XCTestCase {

    private func file(_ path: String, added: Date? = nil) -> FileFacts {
        FileFacts(path: path, bytes: 4_096, fileID: UInt64(abs(path.hashValue)), added: added)
    }
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
    private func rule(_ policy: KeepPolicy) -> KeepRule {
        KeepRule(policy, transit: TransitFolders(roots: []))
    }

    /// The copy with no date is four folders further in and sorts last, so every
    /// rung below the undated one is against it.
    private var copies: [FileFacts] {
        [file("/Users/r/Archive/a.jpg", added: day(400)),
         file("/Users/r/Archive/2019/Old/Deep/z.jpg")]
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
                A blank date read as a loss is the rule `SurvivingCopyTests` records being \
                put back — and read as silence it is the cycle \
                `TheSurvivorDoesNotDependOnWalkOrderTests` records.
                """)
        }
    }

    /// And the header is told which rung it was, because `.date` here would be
    /// «kept: arrived first» about a copy with no arrival on record.
    func testTheReasonIsTheMissingDateAndNotTheDate() {
        for policy in KeepPolicy.allCases {
            XCTAssertEqual(SurvivingCopy.reason(among: copies, by: rule(policy)), .undated,
                           "policy «\(policy.rawValue)»: the rung that decided is the one the "
                           + "header reads, and it is the missing date rather than the date")
        }
    }

    // MARK: - Controls

    /// **The control that keeps the rungs below.** Two copies that both lack a
    /// date are alike on this rung, so it says nothing and the ladder carries on
    /// to the shorter path.
    ///
    /// Without it the repair could be «the deeper copy wins» or «the second copy
    /// wins» and the tests above would not notice.
    func testTwoCopiesWithoutDatesAreAlikeOnThisRung() {
        for policy in KeepPolicy.allCases {
            let ordered = SurvivingCopy.order([file("/Users/r/Archive/2019/Old/deep.jpg"),
                                               file("/Users/r/Archive/shallow.jpg")],
                                              by: rule(policy))
            XCTAssertEqual(ordered[0].path, "/Users/r/Archive/shallow.jpg",
                           "policy «\(policy.rawValue)»: neither has a date, so the missing "
                           + "date separates nothing and the depth rung answers")
            XCTAssertEqual(SurvivingCopy.reason(among: ordered, by: rule(policy)), .depth)
        }
    }

    /// **The control that keeps the date.** Two known dates are still the earlier
    /// copy's win, which is the rung the new one sits above rather than replaces.
    func testTwoKnownDatesAreStillDecidedByTheDate() {
        for policy in KeepPolicy.allCases {
            let dated = [file("/Users/r/Archive/a.jpg", added: day(400)),
                         file("/Users/r/Archive/z.jpg", added: day(100))]
            XCTAssertEqual(SurvivingCopy.order(dated, by: rule(policy))[0].path,
                           "/Users/r/Archive/z.jpg")
            XCTAssertEqual(SurvivingCopy.reason(among: dated, by: rule(policy)), .date,
                           "policy «\(policy.rawValue)»: both dates are known, so the rung "
                           + "above them has nothing to say")
        }
    }
}
