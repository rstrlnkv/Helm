import HelmUI
import XCTest
import Module_Duplicates_Engine
@testable import Module_Duplicates_UI

/// The sentence for the rung the walk-order repair added.
///
/// `TheHeaderSaysWhyACopyStaysTests` next door says every rung gets its own
/// sentence in every language, and its list of grounds is written out by hand —
/// `[.place, .date, .depth, .name]` — so `KeepReason.undated` reached the header
/// without anything asking whether it had a sentence at all. That is the shape
/// this module has paid for once already: one tooltip saying «The copy that was
/// there first» about every group, in eight languages.
///
/// It matters more for this rung than for the four: the copy that stays is the
/// one whose Date Added nothing on this Mac recorded, so the sentence next door
/// — «arrived first» — is the one thing the header must not say about it.
final class TheHeaderSaysWhyAnUndatedCopyStaysTests: XCTestCase {

    private let others: [KeepGrounds] =
        [.place, .date, .depth, .name].map(KeepGrounds.rung) + [.byHand]

    func testItHasASentenceOfItsOwnInEveryLanguage() {
        for language in AppLanguage.allCases {
            let said = DupStr.keptBecause(.rung(.undated), language: language)
            let rest = others.map { DupStr.keptBecause($0, language: language) }
            XCTAssertFalse(rest.contains(said), """
                \(language.rawValue) says «\(said)» for a copy with no date on record, which \
                is what it says for another rung: \(rest). The one it must not borrow is the \
                date's — nothing here knows when this copy arrived, which is the whole reason \
                it is the copy that stays.
                """)
        }
    }

    /// English is the key, so a language whose table never got it reads the
    /// English back — the one failure a coverage check in English cannot see.
    func testItIsTranslatedInEveryLanguage() {
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(DupStr.keptBecause(.rung(.undated), language: language),
                              DupStr.keptBecause(.rung(.undated), language: .en),
                              "\(language.rawValue) is reading the English key back")
        }
    }
}
