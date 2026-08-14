import XCTest
@testable import HelmUI

/// **The lost-reply sentence guaranteed what it could not know.**
///
/// «Helm got no answer, so it does not know what moved. The list above shows
/// where the files are now» was drawn unconditionally — and the rescan that
/// makes its second sentence true is itself a request that may go unanswered.
/// A module whose rescan was lost too drew a promise about a list that had not
/// moved since before the press.
///
/// So there are two of them: the one it was written for — reply lost, rescan
/// answered — and one for the round where nothing came back at all. Two entry
/// points rather than a flag beside the numbers, for the reason `unanswered`
/// itself has one: a lost reply carries no counts, and a caller must not be able
/// to write down «nothing came back, and five moved».
///
/// **Neither sentence names a refresh verb.** The component is drawn from five
/// call sites in four modules and those buttons say three different things —
/// «Scan again», «Search again», «Refresh list» — so a literal would be wrong in
/// two of five, and interpolating one buys an API parameter to point at a button
/// already on the screen.
@MainActor
final class ALostReplyDoesNotPromiseAFreshListTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    /// The fifth verdict, and it is not the fourth: a round where the rescan
    /// answered and one where it did not are different states, and the sentence
    /// is the only thing that can tell the person which they are in.
    func testAStaleListIsNotTheSameVerdictAsAFreshOne() {
        XCTAssertEqual(HelmRemovalOutcome.unansweredWithStaleList.verdict, .unansweredStaleList)
        XCTAssertNotEqual(HelmRemovalOutcome.unansweredWithStaleList.verdict,
                          HelmRemovalOutcome.unanswered.verdict, """
                          a removal whose rescan was also lost draws the sentence promising the \
                          list above is where the files are now.
                          """)
    }

    /// And it carries no numbers either, for the reason the fourth verdict does
    /// not: there are none to carry.
    func testItIsReachedOnlyThroughItsOwnEntryPoint() {
        for (removed, failed) in [(0, 0), (3, 0), (0, 1), (3, 1)] {
            XCTAssertNotEqual(HelmRemovalOutcome.verdict(removed: removed, failed: failed),
                              .unansweredStaleList,
                              "a reply carrying \(removed)/\(failed) read as no reply at all")
        }
    }

    /// The two sentences differ in every language — a second verdict drawing the
    /// first one's words is the promise this exists to withdraw.
    func testTheTwoSentencesAreNotTheSameWordsInAnyLanguage() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertNotEqual(HelmRemovalOutcome.noAnswer, HelmRemovalOutcome.noAnswerStaleList,
                              "\(language.rawValue): both rounds say the same thing")
            XCTAssertFalse(HelmRemovalOutcome.noAnswerStaleList.isEmpty,
                           "\(language.rawValue): the sentence is missing")
        }
    }

    /// **They are one machine fact, so they open the same way.** Two phrasings of
    /// one silence is a defect this codebase keeps finding; the localizer lifted
    /// the opening character for character, and this is what holds it there. The
    /// tails differ on purpose — that is the whole of what the second one says.
    func testBothSentencesOpenWithTheSameClause() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let shared = HelmRemovalOutcome.noAnswer
                .commonPrefix(with: HelmRemovalOutcome.noAnswerStaleList)
            XCTAssertGreaterThanOrEqual(shared.count, 10, """
                \(language.rawValue): the two sentences about one lost reply share only \
                «\(shared)» — one of them has been rewritten and the app now describes the same \
                silence two ways.
                """)
        }
    }
}
