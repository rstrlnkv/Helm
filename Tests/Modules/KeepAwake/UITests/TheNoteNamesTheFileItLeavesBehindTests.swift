import HelmTestSupport
import HelmUI
import XCTest
@testable import Module_KeepAwake_Engine
@testable import Module_KeepAwake_UI

/// What a person reads before they type an administrator password has to name
/// the file that password buys, in every language.
///
/// It is the one disclosure the system's own dialog cannot make: macOS says only
/// that Helm wants to make changes. What the person is agreeing to is a
/// permanent passwordless `pmset disablesleep` for their account, written to a
/// path they can reach with `sudo rm` — and if Helm is deleted while it is
/// running, that path is the only way back to it.
///
/// **The row is no longer where all of that is said, and the promise is
/// unchanged.** The caption had grown to 606 characters in German
/// (`TheLidCaptionFitsUnderTheSwitchTests` has the measurement); the directory
/// stays in the row, and the rule's own path and the command that removes it
/// moved into the explanation behind the ⓘ, which is one press away on the same
/// row and reachable *before* the password is asked for. So this reads both
/// halves — the sentence and what the glyph opens — rather than one string.
///
/// Per language — `AppLanguage.each`, which sets the override and puts it back
/// — because the suite runs in whichever language this machine is set to: a
/// check that reads `AppLanguage.current` inspects one of the eight and reports
/// on all of them. A translator dropping the path — it looks like noise in a
/// sentence — leaves that language with a warning about a file it does not name.
final class TheNoteNamesTheFileItLeavesBehindTests: XCTestCase {

    /// Everything the lid row can put in front of somebody, in the language
    /// under test: the caption and every block behind the glyph.
    private func everythingSaid() -> String {
        let explained = (KAStr.lidExplainer(.whatItCosts)?.blocks ?? []).map { block -> String in
            switch block {
            case .text(let text): return text
            case .command(let command): return command
            }
        }
        return ([KAStr.lidNote(.whatItCosts)] + explained).joined(separator: "\n")
    }

    /// And the path is read from the rule rather than typed here, so this cannot
    /// pass by agreeing with itself about a file the engine stopped writing.
    func testEveryLanguageNamesTheRulesOwnPath() {
        AppLanguage.each { language in
            let said = everythingSaid()
            XCTAssertTrue(said.contains(SudoersRule.installedPath),
                          "\(language.rawValue): the row explains a grant without saying where "
                          + "it lands — «\(said)»")
        }
    }

    /// …and how to take it away when nothing in the app can.
    func testEveryLanguageSaysHowToRemoveItByHand() {
        AppLanguage.each { language in
            XCTAssertTrue(everythingSaid().contains("sudo rm \(SudoersRule.installedPath)"),
                          "\(language.rawValue): no command for the case Helm cannot reach — "
                          + "deleting the app while it runs leaves the rule with no owner")
        }
    }

    /// The command is a command, and the difference is not cosmetic: a line
    /// somebody has to type lands in a `.command` block, which is drawn in a
    /// face that says «type this» and can be selected and copied. Said as prose
    /// it is a sentence with a slash in it.
    func testTheCommandIsOfferedAsOneRatherThanDescribed() {
        AppLanguage.each { language in
            let blocks = KAStr.lidExplainer(.whatItCosts)?.blocks ?? []
            XCTAssertTrue(blocks.contains(.command("sudo rm \(SudoersRule.installedPath)")),
                          "\(language.rawValue): the way out is prose rather than a command "
                          + "— blocks: \(blocks)")
        }
    }
}
