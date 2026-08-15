import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The group header answers the question the tooltip used to answer wrongly.
///
/// It said «The copy that was there first» about every group in every language,
/// which stopped being true the moment the policy existed — and had been a
/// half-truth before that, since the date only ever decided when two dates were
/// known and different. The English key *was* the error, so the fix was to
/// delete it from all eight files rather than to translate it again.
///
/// **Every rung gets its own sentence, in every language.** The reason is the
/// rung that separated this survivor from the copy that came closest, and a
/// header that says the same thing about four different rungs is the tooltip
/// again with more steps.
final class TheHeaderSaysWhyACopyStaysTests: XCTestCase {

    /// Every reason a group can carry. Built from `KeepReason` itself, so a rung
    /// added to the ladder lands here without anybody remembering to add it.
    private let grounds: [KeepGrounds] =
        [.place, .date, .depth, .name].map(KeepGrounds.rung) + [.byHand]

    func testEveryReasonHasItsOwnSentenceInEveryLanguage() {
        for language in AppLanguage.allCases {
            let said = grounds.map { DupStr.keptBecause($0, language: language) }
            XCTAssertEqual(Set(said).count, grounds.count, """
                \(language.rawValue) says the same thing about two different \
                reasons: \(said). A header that cannot tell the rungs apart is \
                the tooltip that said «the copy that was there first» about all \
                of them.
                """)
        }
    }

    /// And it is translated. English is the key, so a language whose table never
    /// got these keys reads back as English — which is the one failure a coverage
    /// test in English cannot see.
    func testTheSentencesAreNotEnglishInEveryLanguage() {
        for language in AppLanguage.allCases where language != .en {
            for ground in grounds {
                XCTAssertNotEqual(DupStr.keptBecause(ground, language: language),
                                  DupStr.keptBecause(ground, language: .en),
                                  "\(language.rawValue) is reading the English key back")
            }
        }
    }

    /// The badge on the row and the reason in the header are two strings about
    /// one fact, and they must not be one key: the header's is a sentence with a
    /// label in front of it, the badge's is two words in a pill.
    func testTheBadgeAndTheHeaderAreNotTheSameKey() {
        XCTAssertNotEqual(DupStr.yourChoice, DupStr.keptBecause(.byHand, language: .en))
    }
}
