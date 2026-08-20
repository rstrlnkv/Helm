import HelmUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// The sentence a person reads before they type an administrator password has to
/// name the file that password buys, in every language.
///
/// It is the one disclosure the system's own dialog cannot make: macOS says only
/// that Helm wants to make changes. What the person is agreeing to is a
/// permanent passwordless `pmset disablesleep` for their account, written to a
/// path they can reach with `sudo rm` — and if Helm is deleted while it is
/// running, that path is the only way back to it.
///
/// Per language, with the override, because the suite runs in whichever
/// language this machine is set to: a check that reads `AppLanguage.current`
/// inspects one of the eight and reports on all of them. A translator dropping
/// the path — it is a long sentence and the path looks like noise — leaves that
/// language with a warning about a file it does not name.
final class TheNoteNamesTheFileItLeavesBehindTests: XCTestCase {

    private var previous: AppLanguage?

    override func setUp() {
        super.setUp()
        previous = AppLanguage.override
    }

    override func tearDown() {
        AppLanguage.override = previous
        super.tearDown()
    }

    /// And the path is read from the rule rather than typed here, so this cannot
    /// pass by agreeing with itself about a file the engine stopped writing.
    func testEveryLanguageNamesTheRulesOwnPath() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertTrue(KAStr.adminNote.contains(SudoersRule.installedPath),
                          "\(language.rawValue): the note explains a grant without saying where "
                          + "it lands — «\(KAStr.adminNote)»")
        }
    }

    /// …and how to take it away when nothing in the app can.
    func testEveryLanguageSaysHowToRemoveItByHand() {
        for language in AppLanguage.allCases {
            AppLanguage.override = language
            XCTAssertTrue(KAStr.adminNote.contains("sudo rm \(SudoersRule.installedPath)"),
                          "\(language.rawValue): no command for the case Helm cannot reach — "
                          + "deleting the app while it runs leaves the rule with no owner")
        }
    }
}
