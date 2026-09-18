import XCTest
import HelmTestSupport
import HelmUI
@testable import Module_Homebrew_Engine
@testable import Module_Homebrew_UI

/// **The ellipsis on a button is a promise that the press opens a question
/// rather than doing the thing — so it goes exactly where a question comes.**
///
/// Uninstall always asks, and its dialog's own confirming button is the one
/// that removes; so the inspector's button reads «Uninstall…» and the dialog's
/// «Uninstall». Run asks for `brew uninstall <name>` and for anything the
/// allowlist has no sentence for, and runs `brew cleanup` on the press — so
/// its label is read off `FixAsk`, the same answer that decides whether the
/// dialog is raised.
///
/// In every language, because the mark is part of each translation and a
/// language that dropped it would tell its reader the press acts at once.
final class AButtonThatAsksSaysItWillAskTests: XCTestCase {

    func testRunPromisesAQuestionExactlyWhenOneIsRaised() {
        let uninstall = DoctorFix(argv: ["uninstall", "periphery"], kind: .runnable)
        let cleanup = DoctorFix(argv: ["cleanup"], kind: .runnable)
        AppLanguage.each { language in
            // The subject first: the two must actually differ in whether they
            // ask, or «one has the mark and one does not» proves nothing.
            XCTAssertNotNil(HomebrewSettingsPage.fixQuestion(uninstall),
                            "\(language.rawValue): uninstalling raises no question")
            XCTAssertNil(HomebrewSettingsPage.fixQuestion(cleanup),
                         "\(language.rawValue): cleanup raises a question")

            XCTAssertTrue(HomebrewSettingsPage.runLabel(uninstall).hasSuffix("…"), """
                \(language.rawValue): Run reads «\(HomebrewSettingsPage.runLabel(uninstall))» over \
                a command that asks before it removes a package — nothing on the button says a \
                question is coming
                """)
            XCTAssertFalse(HomebrewSettingsPage.runLabel(cleanup).hasSuffix("…"), """
                \(language.rawValue): Run reads «\(HomebrewSettingsPage.runLabel(cleanup))» over \
                `brew cleanup`, which runs on the press — the button promises a question that \
                never comes
                """)
        }
    }

    func testTheInspectorsUninstallAsksAndTheDialogsDoesNot() {
        AppLanguage.each { language in
            XCTAssertTrue(HbStr.uninstallAsking.hasSuffix("…"), """
                \(language.rawValue): the inspector's Uninstall reads «\(HbStr.uninstallAsking)», \
                with no mark that pressing it opens a question
                """)
            XCTAssertFalse(HbStr.uninstall.hasSuffix("…"), """
                \(language.rawValue): the dialog's confirming Uninstall reads \
                «\(HbStr.uninstall)» — that button removes the package, and the mark says it would \
                ask again
                """)
        }
    }
}
