import XCTest
import HelmRuntime
@testable import HelmUI

/// The other half of `AFileThatIsGoneIsNotARefusalTests`, one target up: the
/// reason is `HelmRuntime`'s and the sentence is `HelmUI`'s.
///
/// A file that has gone since the scan used to be read out as «macOS would not
/// move this. Show it in the Finder and try from there» — a step that leads to
/// an empty space. Every language has to say something else, and something
/// other than what a file that *moved* is told.
final class AGoneFileGetsItsOwnSentenceTests: XCTestCase {

    /// Parameterized by language rather than gated on `AppLanguage.current`,
    /// which on this Mac is `.ru`: an assertion about "the current language" is
    /// an assertion about whoever ran it.
    func testEveryLanguageSaysItIsGoneRatherThanRefused() {
        let previous = AppLanguage.override
        defer { AppLanguage.override = previous }

        for language in AppLanguage.allCases {
            AppLanguage.override = language
            let gone = TrashReasonText.sentence(TrashFailure.Reason.missing.rawValue)
            let refused = TrashReasonText.sentence(TrashFailure.Reason.systemRefused.rawValue)
            let changed = TrashReasonText.sentence(TrashFailure.Reason.changedSinceScan.rawValue)

            XCTAssertFalse(gone.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(language.rawValue) has nothing to say about a file that has gone")
            XCTAssertNotEqual(gone, refused, """
                \(language.rawValue) still answers a file that is not there with the general \
                refusal, which sends somebody to the Finder to look at it.
                """)
            XCTAssertNotEqual(gone, changed, """
                \(language.rawValue) gives a file that has gone the sentence written for a file \
                that has moved. They are different facts, and only one of them can be acted on.
                """)
        }
    }
}
