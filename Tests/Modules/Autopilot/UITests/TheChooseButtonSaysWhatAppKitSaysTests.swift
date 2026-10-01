import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_Autopilot_UI

/// **The «Choose…» a destination is picked with is AppKit's own word.**
///
/// It is the prompt of the open panel the button raises, so a word of Helm's
/// own there is two names for one button a second apart. The expected values
/// were read out of
/// `/System/Library/Frameworks/AppKit.framework/Versions/C/Resources/Common.loctable`
/// (key `Choose\U2026`; `zh_CN`, `pt_BR`) — German takes an unbreakable space
/// before its ellipsis there, and Spanish and Chinese chose other verbs than
/// the ones Helm had.
///
/// Typed out rather than read at run time, for the reason
/// `TheDisclosureWordsAreMacOSsOwnTests` gives: a test that follows the table
/// can never say the app has drifted from what was chosen.
@MainActor
final class TheChooseButtonSaysWhatAppKitSaysTests: XCTestCase {

    private let words: [AppLanguage: String] = [
        .en: "Choose…",
        .de: "Wählen\u{00A0}…",
        .es: "Seleccionar…",
        .fr: "Choisir…",
        .pt: "Escolher…",
        .ru: "Выбрать…",
        .ja: "選択…",
        .zh: "选取…",
    ]

    func testEveryLanguageSaysAppKitsWord() {
        XCTAssertEqual(Set(words.keys), Set(AppLanguage.allCases), "a language has no expected word")
        AppLanguage.each { language in
            XCTAssertEqual(ApStr.chooseDestination, words[language], language.rawValue)
        }
    }

    /// The German space is the unbreakable one: an ordinary space lets the
    /// ellipsis wrap onto a line of its own under a narrow button.
    func testTheGermanSpaceIsUnbreakable() {
        AppLanguage.only(.de) {
            XCTAssertFalse(ApStr.chooseDestination.contains(" "), "an ordinary space: «\(ApStr.chooseDestination)»")
            XCTAssertTrue(ApStr.chooseDestination.contains("\u{00A0}"))
        }
    }
}
