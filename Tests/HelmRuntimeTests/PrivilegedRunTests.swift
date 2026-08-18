import XCTest
@testable import HelmRuntime

/// «You cancelled» and «the write failed» are different sentences on screen and
/// different next steps. A port that answers `Bool` makes the first a state no
/// fake can be in — the family this app named on 2026-08-12.
final class PrivilegedRunTests: XCTestCase {

    func testACancelledDialogIsNotAFailure() {
        let outcome = PrivilegedRun.outcome(status: 1, output: "User canceled. (-128)")
        XCTAssertEqual(outcome, .declined)
    }

    /// AppleScript's own error number, in case the wording is localized —
    /// `osascript` reports errors in the user's language.
    func testTheCancelIsRecognisedByItsNumberToo() {
        XCTAssertEqual(PrivilegedRun.outcome(status: 1, output: "Пользователь отменил. (-128)"),
                       .declined)
    }

    func testARealFailureCarriesItsStatus() {
        XCTAssertEqual(PrivilegedRun.outcome(status: 2, output: "sh: bad thing"), .failed(2))
    }

    func testSuccessIsSuccess() {
        XCTAssertEqual(PrivilegedRun.outcome(status: 0, output: ""), .done)
    }
}

/// The three-way reading above is only worth having if the text it reads on
/// ever arrives. It does not, by default.
///
/// `osascript(1)`: «e  Print script errors to stderr (default). / o  Print
/// script errors to stdout.» — and `HelmProcess.run` sends the child's stderr
/// to `FileHandle.nullDevice` on purpose. So a
/// cancelled dialog reaches `outcome(status:output:)` as status 1 with an
/// *empty* output, `.declined` is unreachable, and every cancel is reported as
/// a failed write. `-s o` is the half that makes the number arrive.
final class ThePrivilegedRunHearsTheCancelTests: XCTestCase {

    /// The argument list is a seam so this can be pinned without a password
    /// dialog: nothing in this file runs `osascript`.
    func testTheErrorStyleAsksForStdoutBecauseStderrIsDiscarded() {
        let arguments = PrivilegedRun.arguments(for: "/usr/bin/true")
        guard let style = arguments.firstIndex(of: "-s") else {
            return XCTFail("no -s style flag: osascript's errors go to stderr, which HelmProcess drops")
        }
        XCTAssertEqual(arguments[arguments.index(after: style)], "o")
    }

    /// A style flag after the script would be an argument to the script, not to
    /// `osascript`.
    func testTheStyleComesBeforeTheScript() {
        let arguments = PrivilegedRun.arguments(for: "/usr/bin/true")
        guard let style = arguments.firstIndex(of: "-s"),
              let script = arguments.firstIndex(of: "-e") else {
            return XCTFail("expected both -s and -e")
        }
        XCTAssertLessThan(style, script)
    }

    /// The escaping stays in `AppleScript` — one place in this app decides
    /// whether root runs a command or an attacker's continuation of it.
    func testTheScriptIsTheAdministratorFormFromAppleScript() {
        let command = "/bin/echo \"hi\""
        let arguments = PrivilegedRun.arguments(for: command)
        XCTAssertEqual(arguments.last, AppleScript.administratorShellScript(command))
    }
}
