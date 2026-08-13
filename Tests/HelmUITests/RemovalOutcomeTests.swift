import XCTest
@testable import HelmUI

/// The line above a removal that did not entirely work.
///
/// Disk composes its success sentence before it knows the outcome, so a batch
/// where every path refused produced "Removed — 0 bytes freed — 1 item could
/// not be moved": a claim, its own refutation, and two em-dashes, in one
/// caption. Seen on a real run against a read-only folder.
///
/// These assert the shape rather than one language's wording, and they name the
/// language rather than reading `AppLanguage.current`: the suite runs in whatever
/// this machine is set to — `ru-RU` here, not the English CLAUDE.md assumes — so a
/// test that asks `.current` checks one arbitrary language eight times. Measured:
/// with the em dash put back in the *English* branch, the unparameterized version
/// of `testSomethingRemovedKeepsBothHalvesWithoutASecondDash` passed, because it
/// was reading the Russian value the mutation had not touched.
final class RemovalOutcomeTests: XCTestCase {

    private let claim = "REMOVED-CLAIM"

    func testNothingRemovedMeansNoClaimThatAnythingWas() {
        for language in AppLanguage.allCases {
            let line = HelmRemovalOutcome.heading(succeeded: nil, failed: 1, language: language)
            XCTAssertFalse(line.contains("—"),
                           "\(language.rawValue): no dash left where the claim used to be: \(line)")
            XCTAssertFalse(line.isEmpty, "\(language.rawValue): nothing said at all")
        }
    }

    /// The join is a full stop, not a second em dash.
    ///
    /// `succeeded` is the caller's own sentence and already carries one — «Moved
    /// to the Trash: 3 items — 4 KB» — so joining with another put two in one
    /// caption, which is the exact shape the doc comment eight lines above this
    /// component's `init` says was fixed. The Uninstaller's own copy of the line
    /// used a comma, so the app disagreed with itself about it.
    ///
    /// `claim` carries no dash of its own, so any dash in the result came from the
    /// join — which is what makes this readable in all eight at once.
    func testSomethingRemovedKeepsBothHalvesWithoutASecondDash() {
        for language in AppLanguage.allCases {
            let line = HelmRemovalOutcome.heading(succeeded: claim, failed: 1, language: language)
            XCTAssertTrue(line.contains(claim),
                          "\(language.rawValue): the success half is still said: \(line)")
            XCTAssertFalse(line.contains("—"), """
                \(language.rawValue): the heading adds an em dash of its own, and the sentence it \
                is joining to already has one: \(line)
                """)
        }
    }

    /// French spaces its punctuation, and this heading is an inline table —
    /// which is where `PunctuationIsTerminologyTests` cannot look, since that
    /// one reads the eight `.strings` files.
    func testTheFrenchHeadingSpacesItsColonTheWayMacOSDoes() {
        for succeeded in [nil, claim] {
            let line = HelmRemovalOutcome.heading(succeeded: succeeded, failed: 1, language: .fr)
            let characters = Array(line)
            for (index, character) in characters.enumerated() where ":;?!".contains(character) {
                let before = index > 0 ? characters[index - 1] : nil
                XCTAssertNotEqual(before, " ", """
                    an ordinary space before \(character) is a breaking one, so the mark can \
                    start the next line by itself: \(line)
                    """)
            }
        }
    }

    /// The failed count is a counted noun, so the sentence has to change with it
    /// — "1 объект" and "3 объекта" are different words, not a different digit.
    func testTheCountedNounFollowsTheCount() {
        let one = HelmRemovalOutcome.heading(succeeded: nil, failed: 1)
        let three = HelmRemovalOutcome.heading(succeeded: nil, failed: 3)
        XCTAssertNotEqual(one, three)
        XCTAssertTrue(one.contains("1"))
        XCTAssertTrue(three.contains("3"))
    }

    /// The branch that was still not asking.
    ///
    /// `removed` exists because "the sentence cannot be asked whether it is
    /// true", and the failure branch does ask it — but the `failures.isEmpty`
    /// branch printed `succeededText` without ever looking. Callers build that
    /// sentence before they know the outcome and default every count to zero,
    /// so an engine reply carrying nothing at all rendered "Moved to Trash —
    /// 0 bytes freed" while the row it was about was still on screen. Reachable
    /// in the uninstaller's orphans view: paths that were already gone are
    /// deliberately counted as neither trashed nor failed, so both lists come
    /// back empty.
    ///
    /// Nothing happened, so the honest line is no line. That needs no new
    /// wording — the existing sentences are all about something that did.
    func testNothingRemovedAndNothingRefusedSaysNothing() {
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 0, failed: 0), .silent)
    }

    func testSomethingRemovedWithNoRefusalsIsTheSuccessSentence() {
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 3, failed: 0), .succeeded)
    }

    /// A refusal is always worth saying, whether or not anything else worked —
    /// that is the whole reason this component exists.
    func testAnyRefusalIsReported() {
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 0, failed: 1), .failed)
        XCTAssertEqual(HelmRemovalOutcome.verdict(removed: 3, failed: 1), .failed)
    }

    /// The fourth verdict: a reply that never came.
    ///
    /// Not derivable from the numbers, which is why it cannot come from
    /// `verdict(removed:failed:)` — a lost reply has no numbers, and folding it
    /// to zeroes is exactly how three modules turned it into `.silent`. It comes
    /// from its own entry point instead, so «nothing came back, and five moved»
    /// is not a state anybody can build.
    func testAReplyThatNeverCameIsNotSilence() {
        XCTAssertEqual(HelmRemovalOutcome.unanswered.verdict, .unanswered)
        XCTAssertNotEqual(HelmRemovalOutcome.unanswered.verdict, .silent,
                          "a removal nobody answered draws nothing at all")
    }

    /// And a reply that did come never reads as one that did not, whatever it
    /// carried — the half that keeps the new verdict from swallowing the others.
    func testAReplyThatArrivedIsNeverReadAsLost() {
        for (removed, failed) in [(0, 0), (3, 0), (0, 1), (3, 1)] {
            XCTAssertNotEqual(HelmRemovalOutcome.verdict(removed: removed, failed: failed),
                              .unanswered,
                              "a reply carrying \(removed)/\(failed) read as no reply at all")
        }
    }
}
