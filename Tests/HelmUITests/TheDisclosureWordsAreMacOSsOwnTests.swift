import XCTest
import HelmTestSupport
@testable import HelmUI

/// **The words a disclosure says are the ScreenReader table's, in every
/// language, and there is one pair of them.**
///
/// The expected values were read out of
/// `/System/Library/PrivateFrameworks/ScreenReader.framework/Versions/A/Resources/SCRGeneral.loctable`
/// (stand-alone `expanded` and `collapsed`; `zh_CN`, `pt_BR`), lower-cased.
/// Japanese `expanded` is the one entry not used: there it is 字間広く, a
/// typography term, and the table's `row %lu expanded` says 表示されました.
///
/// They are typed out here rather than read from the table at run time because
/// a Mac in another release may word them differently, and a test that follows
/// the table can never say the app has drifted from what was chosen.
final class TheDisclosureWordsAreMacOSsOwnTests: XCTestCase {

    private let words: [AppLanguage: (expanded: String, collapsed: String)] = [
        .en: ("expanded", "collapsed"),
        .de: ("erweitert", "reduziert"),
        .es: ("ampliado", "contraído"),
        .fr: ("étendu", "condensé"),
        .pt: ("expandido", "reduzido"),
        .ru: ("развернутая", "свернутая"),
        .ja: ("表示されました", "下位項目が折りたたまれました"),
        .zh: ("已展开", "已折叠"),
    ]

    func testEveryLanguageSaysTheSystemsWords() {
        XCTAssertEqual(Set(words.keys), Set(AppLanguage.allCases), "a language has no expected pair")
        AppLanguage.each { language in
            guard let expected = words[language] else { return }
            XCTAssertEqual(HelmA11y.expanded(true), expected.expanded, language.rawValue)
            XCTAssertEqual(HelmA11y.expanded(false), expected.collapsed, language.rawValue)
        }
    }

    /// The Homebrew tab's own pair was deleted; a key of that spelling coming
    /// back would be a second account of one state.
    func testNoSecondPairOfKeysExists() throws {
        let english = try RepoSource.text(of: "Sources/HelmUI/Resources/en.lproj/Localizable.strings")
        XCTAssertNil(english.range(of: "\"Expanded\" ="))
        XCTAssertNil(english.range(of: "\"Collapsed\" ="))
        XCTAssertNotNil(english.range(of: "\"expanded\" ="), "the shared key must be there for the test to mean anything")
    }
}
