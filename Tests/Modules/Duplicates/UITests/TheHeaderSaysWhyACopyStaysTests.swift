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

    /// Every reason a group can carry.
    ///
    /// **Written by hand, and this comment used to say it was built from
    /// `KeepReason` itself «so a rung added to the ladder lands here without
    /// anybody remembering to add it».** It was `[.place, .date, .depth, .name]`
    /// then and it is a literal now: `KeepReason` is not `CaseIterable`, so
    /// nothing here can enumerate it. The rung the walk-order repair added,
    /// `.undated`, reached the header while this file went on checking four of
    /// five — the omission the comment claimed was impossible, and a sentence
    /// nobody had asked about is what this file exists to catch.
    ///
    /// `testAddingARungToTheLadderStopsTheBuildHere` is what the comment
    /// promised, as far as a test target can carry it.
    private let grounds: [KeepGrounds] =
        [.place, .undated, .date, .depth, .name].map(KeepGrounds.rung) + [.byHand]

    /// **A rung added to `KeepReason` is a build error in this file.** The switch
    /// is exhaustive and has no `default`, so a sixth case stops the compiler
    /// here; putting it in the list above is then the only way to build, and the
    /// tests below cover it from that moment.
    ///
    /// The runtime half catches the other order of events — a case spelled here
    /// and forgotten in the list — which is what happens when the build error is
    /// answered by adding a `case` and nothing else.
    func testAddingARungToTheLadderStopsTheBuildHere() {
        for rung in [KeepReason.place, .undated, .date, .depth, .name] {
            switch rung {
            case .place, .undated, .date, .depth, .name: break
            }
            XCTAssertTrue(grounds.contains(.rung(rung)), """
                `\(rung.rawValue)` is a rung the ladder can report and it is not among the \
                grounds this file checks, so nothing here asks whether the header has a \
                sentence for it. That is how `.undated` reached the page unchecked: the \
                list is a literal, and the compiler only guards the switch above it.
                """)
        }
    }

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
