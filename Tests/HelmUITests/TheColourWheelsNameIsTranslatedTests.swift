import Foundation
import HelmTestSupport
import HelmUI
import XCTest

/// **«All Colours», the name of the editor's colour wheel, has its own line in each of the eight folders and is
/// said differently in each.** `StringsCoverageTests` reads `en.lproj`'s keys and looks for each in the other seven; this
/// asks what a present-but-English line would pass: that the seven say it in their own words, not the English left
/// standing (a missing line reads as its own key, which is English). That no other cell shares the name is asked in
/// the module's `TheColourWheelOpensTheEightInksTests`.
final class TheColourWheelsNameIsTranslatedTests: XCTestCase {

    private let key = "All Colours"

    func testTheKeyHasALineInEveryFolder() throws {
        var folders = 0
        for language in AppLanguage.allCases {
            let url = try XCTUnwrap(RepoSource.root.appendingPathComponent("Sources/HelmUI/Resources/\(language.rawValue).lproj/Localizable.strings") as URL?)
            let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String], "\(language): the table did not parse")
            XCTAssertNotNil(table[key], "\(language): no line for «\(key)»")
            folders += 1
        }
        XCTAssertEqual(folders, 8)
    }

    func testEachLanguageSaysItItsOwnWay() {
        var said: [AppLanguage: String] = [:]
        AppLanguage.each { language in said[language] = L(key, language: language) }
        XCTAssertEqual(said[.en], "All Colours", "the English line is the key")
        for (language, text) in said where language != .en {
            XCTAssertNotEqual(text, key, "\(language): left in English")
            XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(language): empty")
        }
        XCTAssertEqual(Set(said.values).count, 8, "two languages share a line: \(said)")
    }
}
