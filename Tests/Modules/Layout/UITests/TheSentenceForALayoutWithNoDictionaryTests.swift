import HelmUI
import XCTest
@testable import Module_Layout_UI

/// What the page says when macOS has no dictionary for a layout somebody has
/// installed — Kazakh, Belarusian, Georgian, Armenian, Serbian, Thai, Japanese
/// and Chinese are all absent from `NSSpellChecker.availableLanguages`, measured
/// at 44 entries on this Mac.
///
/// **The sentence has to say what still works.** «Fix as I type» is dead for
/// every pair that includes such a layout, because the verdict needs the
/// dictionary on both sides — but `LayoutVerdict.decideForced`, which the
/// gesture uses, asks no dictionary at all. «Helm cannot decide for itself
/// here» and «this does not work here» read very differently to somebody who
/// has just switched a language on, and only the first is true.
@MainActor
final class TheSentenceForALayoutWithNoDictionaryTests: XCTestCase {

    /// The layout is named, in every language rather than in whichever one this
    /// Mac happens to be set to.
    func testTheLayoutIsNamedInEveryLanguage() {
        for language in AppLanguage.allCases {
            let line = LyStr.noDictionary(layouts: "Қазақша", language: language)
            XCTAssertTrue(line.contains("Қазақша"),
                          "\(language) did not name the layout: \(line)")
        }
    }

    /// Two layouts arrive already joined, so the sentence must not assume one.
    func testMoreThanOneLayoutFits() {
        let line = LyStr.noDictionary(layouts: "Қазақша, ქართული", language: .en)
        XCTAssertTrue(line.contains("Қазақша, ქართული"), line)
    }

    /// The half that keeps this from reading as «the module is broken».
    func testEveryLanguageSaysTheGestureStillWorks() {
        // The English key, and the seven translations, each carrying their own
        // word for the key that still converts.
        let mentionsTheKey: [AppLanguage: String] = [
            .en: "key", .ru: "клавише", .es: "tecla", .fr: "touche",
            .de: "Taste", .pt: "tecla", .ja: "キー", .zh: "按键",
        ]
        for language in AppLanguage.allCases {
            let line = LyStr.noDictionary(layouts: "Қазақша", language: language)
            let word = mentionsTheKey[language] ?? ""
            XCTAssertTrue(line.contains(word),
                          "\(language) reads as «this does not work» — it never says the "
                          + "gesture still converts: \(line)")
        }
    }

    /// And it is not the English sentence seven times over.
    func testTheTranslationsAreTranslations() {
        let english = LyStr.noDictionary(layouts: "Қазақша", language: .en)
        for language in AppLanguage.allCases where language != .en {
            XCTAssertNotEqual(LyStr.noDictionary(layouts: "Қазақша", language: language), english,
                              "\(language) is untranslated")
        }
    }
}
