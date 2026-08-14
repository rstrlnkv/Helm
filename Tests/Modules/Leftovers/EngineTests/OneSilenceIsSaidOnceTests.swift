import XCTest
import Module_Leftovers_Engine

/// **Two requests on this page can go unanswered, and they meet on the first
/// press that fails.**
///
/// `LeftoversViewModel.trash` rescans on the lost-reply path, so a removal whose
/// reply never came is followed immediately by a scan that may not come either.
/// The removal's own sentence then has to say that the list is from *before* the
/// press — and the rescan's sentence must not also be drawn, or one machine fact
/// is announced twice in two phrasings, which is the defect this codebase keeps
/// catching.
///
/// The rule is here rather than in the view because it is a rule about what the
/// page may claim, and a `switch` in a `body` is a rule nobody can test.
final class OneSilenceIsSaidOnceTests: XCTestCase {

    /// A page nobody has pressed anything on says nothing about silence.
    func testAnAnsweredPageHasNothingToSay() {
        XCTAssertNil(LeftoversSilence.note(removalUnanswered: false, rescanUnanswered: false,
                                           scanned: true))
    }

    /// The removal's reply was lost and the rescan answered: the list under the
    /// sentence is current, so the sentence may point at it.
    func testALostRemovalOverAFreshListIsTheRemovalsOwnSentence() {
        XCTAssertEqual(LeftoversSilence.note(removalUnanswered: true, rescanUnanswered: false,
                                             scanned: true),
                       .removalLost)
    }

    /// Both lost. One sentence covers both, and it is the removal's — the press
    /// is what the person is waiting on, and the list being old is the same
    /// silence read from the other end.
    func testBothLostIsOneSentenceAndItIsTheRemovals() {
        XCTAssertEqual(LeftoversSilence.note(removalUnanswered: true, rescanUnanswered: true,
                                             scanned: true),
                       .removalAndListLost, """
                       a removal nobody answered followed by a rescan nobody answered draws two \
                       sentences about one silence, and the removal's promises a list the rescan \
                       never delivered.
                       """)
    }

    /// A rescan nobody answered, with no removal behind it: the Scan button was
    /// pressed and the page went on showing the previous scan's list in silence.
    func testARescanNobodyAnsweredSaysSoOnItsOwn() {
        XCTAssertEqual(LeftoversSilence.note(removalUnanswered: false, rescanUnanswered: true,
                                             scanned: true),
                       .listLost)
    }

    /// **And not before there is a list.** The first scan of the session going
    /// unanswered leaves `scanned` false and the page on its invitation — «the
    /// list above is still from the previous scan» would name a list that has
    /// never been drawn.
    func testAFirstScanThatWasLostNamesNoPreviousList() {
        XCTAssertNil(LeftoversSilence.note(removalUnanswered: false, rescanUnanswered: true,
                                           scanned: false), """
                     the page invites the person to scan and tells them underneath that the list \
                     above is from a previous scan, with no list above and no previous scan.
                     """)
    }
}
