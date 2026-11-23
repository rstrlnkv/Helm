import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorFix.judge` — the one place that decides whether a command `brew
/// doctor` printed may ever be handed to a process.
///
/// Every case here is written so that it goes red when the rule is loosened in
/// the direction it guards. The loosenings were planted one at a time and each
/// case was watched to fail; the report beside this work names them. A case
/// that cannot fail is not a guard, and this file is the security surface of
/// the whole «Состояние» design.
final class OnlyAnAllowedFixMayBeRunTests: XCTestCase {

    /// What this Mac actually had installed when the fixture output was
    /// captured, plus two neighbours — so "is in the installed list" is
    /// exercised against a list with more than one entry in it.
    private let installed = ["periphery", "git", "python@3.12"]

    // MARK: - The one entry, from the front

    func testUninstallingAnInstalledPackageIsRunnable() {
        let fix = DoctorFix.judge(["uninstall", "periphery"], installed: installed)
        XCTAssertEqual(fix.kind, .runnable)
        XCTAssertEqual(fix.argv, ["uninstall", "periphery"],
                       "judge repeats the argv it was given; it does not rewrite one")
    }

    /// `cleanup` is no entry: no page offers it (defect M031), so the bare
    /// command is refused like any other the list does not name.
    func testCleanupIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["cleanup"], installed: installed).kind, .copyOnly)
    }

    /// A name with the characters a real Homebrew name carries — `@`, a digit,
    /// a dot — is still runnable when it is installed. Without this the
    /// character rule could be tightened to letters alone and nothing would say
    /// so until somebody with `python@3.12` opened the page.
    func testAnInstalledNameCarryingAtAndADotIsRunnable() {
        XCTAssertEqual(DoctorFix.judge(["uninstall", "python@3.12"], installed: installed).kind,
                       .runnable)
    }

    // MARK: - The name came out of text

    func testUninstallingSomethingThisMacDoesNotHaveIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["uninstall", "something-not-installed"],
                                       installed: installed).kind,
                       .copyOnly)
    }

    func testUninstallWithTwoNamesIsCopyOnlyEvenWhenBothAreInstalled() {
        XCTAssertEqual(DoctorFix.judge(["uninstall", "periphery", "git"], installed: installed).kind,
                       .copyOnly,
                       "the allowlist is argument-exact, and a second name is a second act")
    }

    func testUninstallWithNoNameAtAllIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["uninstall"], installed: installed).kind, .copyOnly)
    }

    // MARK: - The ones a reader expects and that are deliberately absent

    func testUntapIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["untap", "sozercan/homebrew-repo"],
                                       installed: installed).kind,
                       .copyOnly,
                       "untap takes everything installed from that tap with it")
    }

    func testUpdateResetIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["update-reset"], installed: installed).kind, .copyOnly,
                       "update-reset discards local taps")
    }

    // MARK: - Arguments are part of the match, not decoration

    /// An argument spelled like a name, which the character rule has no
    /// opinion about: it goes red the moment an entry is matched on a prefix.
    /// `brew cleanup periphery` cleans one package's downloads.
    func testCleanupWithANameBesideItIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["cleanup", "periphery"], installed: installed).kind,
                       .copyOnly)
    }

    /// Held by two rules at once — the character rule refuses a leading `-`,
    /// and the match is argument-exact — so it takes both being loosened
    /// together to make it red.
    func testCleanupWithAPruneArgumentIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["cleanup", "--prune=all"], installed: installed).kind,
                       .copyOnly)
    }

    func testAnEmptyArgvIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge([], installed: installed).kind, .copyOnly)
    }

    // MARK: - `brew` is not part of an argv this judge accepts

    /// Decided, and written in the file's doc comment: `judge` is handed the
    /// subcommand and its operands, exactly the shape the module's own launch
    /// sites pass to the brew executable. An argv that still carries `brew` at
    /// the front has not been parsed, and stripping it would be a
    /// normalisation — the judge does none.
    func testAnArgvStillCarryingBrewAtTheFrontIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["brew", "cleanup"], installed: installed).kind, .copyOnly)
        XCTAssertEqual(DoctorFix.judge(["brew", "uninstall", "periphery"],
                                       installed: installed).kind,
                       .copyOnly)
    }

    // MARK: - No normalisation: case, padding, or a tab doing a separator's job

    func testAnUppercasedSubcommandIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["UNINSTALL", "periphery"], installed: installed).kind,
                       .copyOnly)
    }

    func testASubcommandPaddedWithSpacesIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge([" uninstall ", "periphery"], installed: installed).kind,
                       .copyOnly)
    }

    func testASubcommandAndANameInOneElementSplitByATabIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["uninstall\tperiphery"], installed: installed).kind,
                       .copyOnly)
    }

    // MARK: - A hostile element, one character per case
    //
    // Each of these passes the name through the installed list as well — the
    // installed list is itself a list parsed out of another tool's output, so
    // "it is in the installed list" is not proof that a string is a name. That
    // is what makes each case able to fail: remove the character rule and the
    // exact match alone lets every one of them through.

    func testASemicolonInANameIsCopyOnly() {
        let name = "periphery;rm"
        XCTAssertEqual(DoctorFix.judge(["uninstall", name], installed: installed + [name]).kind,
                       .copyOnly)
    }

    func testAnAmpersandPairInANameIsCopyOnly() {
        let name = "periphery&&rm"
        XCTAssertEqual(DoctorFix.judge(["uninstall", name], installed: installed + [name]).kind,
                       .copyOnly)
    }

    func testACommandSubstitutionInANameIsCopyOnly() {
        let name = "periphery$(rm)"
        XCTAssertEqual(DoctorFix.judge(["uninstall", name], installed: installed + [name]).kind,
                       .copyOnly)
    }

    func testABacktickInANameIsCopyOnly() {
        let name = "periphery`rm`"
        XCTAssertEqual(DoctorFix.judge(["uninstall", name], installed: installed + [name]).kind,
                       .copyOnly)
    }

    func testANewlineInANameIsCopyOnly() {
        let name = "periphery\nrm"
        XCTAssertEqual(DoctorFix.judge(["uninstall", name], installed: installed + [name]).kind,
                       .copyOnly)
    }

    func testANameBeginningWithADashIsCopyOnly() {
        let name = "-n"
        XCTAssertEqual(DoctorFix.judge(["uninstall", name], installed: installed + [name]).kind,
                       .copyOnly,
                       "brew would read it as an option, not as the package it is standing in for")
    }

    func testAnEmptyElementIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["uninstall", ""], installed: installed + [""]).kind,
                       .copyOnly)
    }

    // MARK: - The list itself

    /// The hand-written list, named entry by entry. A second entry cannot be
    /// added without this failing, which is the point: the checklist a new
    /// entry has to pass is written in `DoctorFix.swift` beside the list, and
    /// this is what sends its author to read it.
    func testTheAllowlistHoldsExactlyThisOneEntry() {
        XCTAssertEqual(DoctorFix.Allowed.allCases, [.uninstallAnInstalledPackage])
    }

    /// The entry admits its own command and nothing else — so it cannot be
    /// quietly widened.
    func testTheEntryAdmitsOnlyItsOwnCommand() {
        XCTAssertTrue(DoctorFix.Allowed.uninstallAnInstalledPackage
            .admits(["uninstall", "periphery"], installed: installed))
        XCTAssertFalse(DoctorFix.Allowed.uninstallAnInstalledPackage.admits(["cleanup"],
                                                                           installed: installed))
    }
}
