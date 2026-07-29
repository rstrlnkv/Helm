import XCTest
@testable import HelmUI

/// "Move N things (size) to the Trash?" was written out in eight languages four
/// times — Disk, Uninstaller, Leftovers, Duplicates — and the four had already
/// drifted, which is the whole argument for one copy.
///
/// The drift was in French, and it was not a matter of taste. macOS's own verb
/// for this is **"Placer dans la corbeille"** (27 tables to 0 for any other),
/// and macOS puts U+00A0 before a question mark in French — counted over the
/// 13 808 `.loctable` files this machine ships, 683 against 3 for an ordinary
/// space. Three of the four copies invented the verb *and* used a breaking
/// space, so the question mark could fall to the line below on its own.
final class ConfirmTrashTests: XCTestCase {

    private static let nbsp = "\u{00A0}"

    /// The verb and the spacing are the two things the copies got wrong, so
    /// they are the two things pinned.
    func testFrenchUsesMacOSVerbAndKeepsItsQuestionMark() {
        let sentence = HelmConfirm.trash("3 éléments", "1,5 Go", language: .fr)

        XCTAssertEqual(sentence, "Placer 3 éléments (1,5 Go) dans la corbeille\(Self.nbsp)?")
        XCTAssertFalse(sentence.hasSuffix(" ?"),
                       "an ordinary space lets the question mark break onto its own line")
    }

    func testEveryLanguageNamesTheTrashTheWayMacOSNamesIt() {
        let expected: [AppLanguage: String] = [
            .en: "Trash", .ru: "Корзину", .es: "papelera", .fr: "corbeille",
            .de: "Papierkorb", .ja: "ゴミ箱", .zh: "废纸篓", .pt: "Lixo",
        ]
        for (language, word) in expected {
            XCTAssertTrue(HelmConfirm.trash("X", "Y", language: language).contains(word),
                          "\(language) does not name the Trash as macOS does")
        }
    }

    /// The subject and the size are the caller's — a module that counts files
    /// says files, one that counts items says items — so both must survive into
    /// every language rather than being dropped by a table entry that forgot a
    /// placeholder.
    func testTheSubjectAndTheSizeSurviveInEveryLanguage() {
        for language in AppLanguage.allCases {
            let sentence = HelmConfirm.trash("SUBJECT", "SIZE", language: language)
            XCTAssertTrue(sentence.contains("SUBJECT"), "\(language) dropped the subject")
            XCTAssertTrue(sentence.contains("SIZE"), "\(language) dropped the size")
        }
    }

    /// Eight languages, and none of them silently falling back to the English
    /// sentence — which is what a missing table entry looks like from outside.
    func testNoLanguageFallsBackToEnglish() {
        let english = HelmConfirm.trash("X", "Y", language: .en)
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(HelmConfirm.trash("X", "Y", language: language), english,
                              "\(language) has no translation of its own")
        }
    }

    func testTheDefaultFollowsTheAppsLanguage() {
        XCTAssertEqual(HelmConfirm.trash("X", "Y"),
                       HelmConfirm.trash("X", "Y", language: AppLanguage.current))
    }
}
