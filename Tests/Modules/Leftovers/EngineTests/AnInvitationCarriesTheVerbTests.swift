import XCTest
@testable import Module_Leftovers_Engine

/// Which of the three empty screens is an **invitation** — and therefore carries
/// the verb — and which are statements.
///
/// `HelmEmptyState`'s own documentation splits the two: an invitation gets the
/// symbol and the button, a statement is a sentence and nothing else, because a
/// button on a statement invites somebody to repeat what just came back empty.
/// The page gave all three no `actions:` at all, so the first screen a person
/// ever sees asked to be scanned with no way to scan from it — the only «Scan»
/// was in the toolbar, 374 pt above the sentence inviting it and 400 pt to its
/// right.
///
/// Over the enum and exhaustive, for the reason `LfStr.emptyMessage` records: a
/// `default` here is how a fourth state would come to be given a verb, or lose
/// one, without anybody deciding.
final class AnInvitationCarriesTheVerbTests: XCTestCase {

    /// Nothing has been asked yet, and asking is the whole point of the screen.
    func testTheFirstScreenIsAnInvitation() {
        XCTAssertTrue(LeftoversEmpty.invites(.notScanned))
    }

    /// «No leftovers found» is an answer. A button here would offer to run the
    /// scan that has just answered.
    func testACleanMacIsAStatementAndNotAnInvitation() {
        XCTAssertFalse(LeftoversEmpty.invites(.nothingFound))
    }

    /// And when the filter is what emptied the list, the verb the person wants is
    /// in the menu directly above the message — not a second scan of the same Mac.
    func testAFilteredListIsNotInvitedToScanAgain() {
        XCTAssertFalse(LeftoversEmpty.invites(.hiddenByFilter))
    }
}
