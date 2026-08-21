import XCTest
import HelmUI
@testable import Module_Autopilot_Engine
@testable import Module_Autopilot_UI

/// The banner a person reads at seven in the morning, in every language Helm
/// ships.
///
/// Parameterized by an explicit language rather than reading `AppLanguage.current`:
/// the suite runs in whatever this machine is set to, so a test gated on
/// `.current` exercises one of the eight and reports on all of them.
final class TheSweepBannerSpeaksEightLanguagesTests: XCTestCase {

    private func tally(trashed: Int = 0, refused: Int = 0, failed: Int = 0) -> SweepNews.Tally {
        SweepNews.Tally(trashed: trashed, refused: refused, failed: failed)
    }

    func testTheBinnedClauseIsWrittenInEveryLanguage() {
        var seen: Set<String> = []
        for language in AppLanguage.allCases {
            let said = ApStr.sweepTrashed(3, language: language)
            XCTAssertTrue(said.contains("3"), "\(language.rawValue) lost the count: \(said)")
            seen.insert(said)
        }
        XCTAssertEqual(seen.count, AppLanguage.allCases.count,
                       "two languages read identically, so at least one is untranslated: \(seen)")
    }

    func testTheRefusedClauseIsWrittenInEveryLanguage() {
        var seen: Set<String> = []
        for language in AppLanguage.allCases {
            let said = ApStr.sweepNotActedOn(2, language: language)
            XCTAssertTrue(said.contains("2"), "\(language.rawValue) lost the count: \(said)")
            seen.insert(said)
        }
        XCTAssertEqual(seen.count, AppLanguage.allCases.count,
                       "two languages read identically, so at least one is untranslated: \(seen)")
    }

    /// The counted noun takes the form the language gives it: «1 файл»,
    /// «3 файла», «5 файлов». A number interpolated in front of a fixed word
    /// reads as a bug to the person looking at the banner.
    func testTheCountedNounFollowsItsLanguagesRules() {
        XCTAssertTrue(ApStr.sweepTrashed(1, language: .ru).contains("1 файл"))
        XCTAssertTrue(ApStr.sweepTrashed(3, language: .ru).contains("3 файла"))
        XCTAssertTrue(ApStr.sweepTrashed(5, language: .ru).contains("5 файлов"))
        XCTAssertTrue(ApStr.sweepTrashed(1, language: .en).contains("1 file"))
        XCTAssertFalse(ApStr.sweepTrashed(1, language: .en).contains("1 files"))
    }

    // MARK: - What the body is made of

    /// **A finding about the Trash, and nothing else, when nothing else
    /// happened.** The body is assembled from the tally, so a pass that only
    /// binned must not carry an empty second clause and its separator.
    func testATallyWithOnlyBinnedFilesIsOneClause() {
        for language in AppLanguage.allCases {
            let body = ApStr.sweepNotice(tally(trashed: 2), language: language).body
            XCTAssertEqual(body, ApStr.sweepTrashed(2, language: language))
            XCTAssertFalse(body.hasSuffix(" · "), "\(language.rawValue) drew a dangling separator")
        }
    }

    /// And the other way round: a pass that binned nothing and refused two says
    /// only that.
    func testATallyWithOnlyRefusalsIsTheOtherClause() {
        for language in AppLanguage.allCases {
            let body = ApStr.sweepNotice(tally(refused: 1, failed: 1), language: language).body
            XCTAssertEqual(body, ApStr.sweepNotActedOn(2, language: language))
        }
    }

    /// Both, joined — and the refusals and the failures counted together,
    /// because what the banner owes the person is that a rule did not run.
    func testBothClausesAreJoinedInOrder() {
        for language in AppLanguage.allCases {
            let body = ApStr.sweepNotice(tally(trashed: 1, refused: 1, failed: 2),
                                         language: language).body
            XCTAssertEqual(body, ApStr.sweepTrashed(1, language: language) + " · "
                               + ApStr.sweepNotActedOn(3, language: language))
        }
    }

    /// A notification with no title is drawn as the app's name and a body, and
    /// «Helm» does not say which of ten modules is speaking.
    func testTheBannerNamesTheModule() {
        for language in AppLanguage.allCases {
            XCTAssertEqual(ApStr.sweepNotice(tally(trashed: 1), language: language).title,
                           L("Autopilot", language: language))
        }
    }

    /// French puts a narrow no-break space before its two-part punctuation, and
    /// a plain space there is the mistake a translation review catches last.
    func testTheFrenchClausesCarryNoBareSpaceBeforeTightPunctuation() {
        for said in [ApStr.sweepTrashed(3, language: .fr),
                     ApStr.sweepNotActedOn(3, language: .fr),
                     ApStr.sweepNotice(tally(trashed: 1, refused: 1), language: .fr).body] {
            for mark in [":", ";", "?", "!", "»"] {
                XCTAssertFalse(said.contains(" " + mark),
                               "a bare space before \(mark) in: \(said)")
            }
        }
    }
}
