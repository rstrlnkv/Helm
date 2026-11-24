import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorFix.judge`, the one place that decides whether a command `brew
/// doctor` printed may ever be handed to a process.
///
/// Every case goes red when the rule is loosened in the direction it guards;
/// this file is the security surface of the whole Health tab.
final class OnlyAnAllowedFixMayBeRunTests: XCTestCase {

    /// This Mac's installed list at the capture, plus two neighbours, so "is in
    /// the installed list" is tried against more than one entry.
    private let installed = ["periphery", "git", "python@3.12"]

    // MARK: - The one entry, from the front

    func testUninstallingAnInstalledPackageIsRunnable() {
        let fix = DoctorFix.judge(["uninstall", "periphery"], installed: installed)
        XCTAssertEqual(fix.kind, .runnable)
        XCTAssertEqual(fix.argv, ["uninstall", "periphery"],
                       "judge repeats the argv it was given; it does not rewrite one")
    }

    /// `cleanup` is no entry: no page offers it, so the bare command is
    /// refused like any other the list does not name.
    func testCleanupIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["cleanup"], installed: installed).kind, .copyOnly)
    }

    /// A name with the characters a real Homebrew name carries (`@`, a digit, a
    /// dot) is runnable when installed, so the character rule cannot shrink to
    /// letters alone unnoticed.
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

    /// Held by two rules at once (the character rule refuses a leading `-`, and
    /// the match is argument-exact), so both must loosen to make it red.
    func testCleanupWithAPruneArgumentIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge(["cleanup", "--prune=all"], installed: installed).kind,
                       .copyOnly)
    }

    func testAnEmptyArgvIsCopyOnly() {
        XCTAssertEqual(DoctorFix.judge([], installed: installed).kind, .copyOnly)
    }

    // MARK: - `brew` is not part of an argv this judge accepts

    /// `judge` is handed the subcommand and its operands, the shape the
    /// module's own launch sites pass to brew. An argv still carrying `brew` at
    /// the front has not been parsed, and the judge does no normalisation.
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
    // Each name also passes the installed list, itself parsed out of another
    // tool's output, so "it is in the installed list" is no proof of a name.
    // Without the character rule, the exact match alone lets every one through.

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
    /// added without this failing, which sends its author to the checklist
    /// beside the list in `DoctorFix.swift`.
    func testTheAllowlistHoldsExactlyThisOneEntry() {
        XCTAssertEqual(DoctorFix.Allowed.allCases, [.uninstallAnInstalledPackage])
    }

    /// The entry admits its own command and nothing else.
    func testTheEntryAdmitsOnlyItsOwnCommand() {
        XCTAssertTrue(DoctorFix.Allowed.uninstallAnInstalledPackage
            .admits(["uninstall", "periphery"], installed: installed))
        XCTAssertFalse(DoctorFix.Allowed.uninstallAnInstalledPackage.admits(["cleanup"],
                                                                           installed: installed))
    }
}
