import XCTest
@testable import HelmRuntime

/// «You cancelled» and «the write failed» are different sentences on screen and
/// different next steps. A port that answers `Bool` makes the first a state no
/// fake can be in.
final class PrivilegedRunTests: XCTestCase {

    func testACancelledDialogIsNotAFailure() {
        let outcome = PrivilegedRun.outcome(status: 1, output: "User canceled. (-128)")
        XCTAssertEqual(outcome, .declined)
    }

    /// AppleScript's own error number, because `osascript` reports errors in
    /// the user's language, so nothing in the sentence beside the number can be
    /// matched on. Verbatim from row 2 of the measurement in
    /// `PrivilegedRun.arguments(for:)`.
    func testTheCancelIsRecognisedByItsNumberToo() {
        XCTAssertEqual(
            PrivilegedRun.outcome(status: 1,
                                  output: "0:17: execution error: Отменено пользователем. (-128)"),
            .declined)
    }

    func testARealFailureCarriesItsStatus() {
        XCTAssertEqual(PrivilegedRun.outcome(status: 2, output: "sh: bad thing"), .failed(2))
    }

    func testSuccessIsSuccess() {
        XCTAssertEqual(PrivilegedRun.outcome(status: 0, output: ""), .done)
    }
}

/// The three-way reading above needs the text it reads to arrive. `osascript`
/// prints script errors to stderr by default, and `HelmProcess.run` discards
/// the child's stderr, so a cancel would arrive as status 1 with empty output
/// and read as a failed write. `-s o` sends the errors to stdout.
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

    /// A quote in the command is escaped before it reaches the script, so it
    /// cannot end the literal and let the rest run as AppleScript under root.
    /// Spelled out, not computed by `AppleScript`: a missing escape would then
    /// agree with itself.
    func testAQuoteAndABackslashInTheCommandAreEscapedInTheScript() {
        let arguments = PrivilegedRun.arguments(for: #"/bin/echo "a\b""#)
        XCTAssertEqual(arguments.last,
                       #"do shell script "/bin/echo \"a\\b\"" with administrator privileges"#)
    }
}

/// `do shell script` puts the failing command's **own output** inside the error
/// it raises, and that output is text this app never wrote and cannot predict.
/// So the cancel has to be matched on the shape `osascript` actually prints —
/// `(-128)`, parentheses included — and not on a bare `-128` that any path,
/// any version string and any other error number can carry through.
final class TheCancelIsMatchedOnItsShapeTests: XCTestCase {

    /// A path with the digits in it. The whole message is somebody else's,
    /// arriving verbatim inside AppleScript's error; a bare-substring match
    /// reads this as «the person pressed Cancel» and reports a failed write as
    /// a polite refusal.
    func testDigitsInsideBorrowedOutputAreNotACancel() {
        XCTAssertEqual(
            PrivilegedRun.outcome(status: 1,
                                  output: "0:0: execution error: rm: /tmp/build-128/x: "
                                        + "No such file or directory (1)"),
            .failed(1))
    }

    /// A different number that merely opens with the same digits. The match is
    /// the closing parenthesis as much as the opening one.
    func testALongerNumberBeginningWithTheSameDigitsIsNotACancel() {
        XCTAssertEqual(PrivilegedRun.outcome(status: 1, output: "execution error: something (-1280)"),
                       .failed(1))
    }

    /// Row 3 of the measurement in `PrivilegedRun.arguments(for:)`: a genuine
    /// script error, verbatim, and it is not a cancel.
    func testAScriptErrorThatIsNotACancelKeepsItsStatus() {
        XCTAssertEqual(
            PrivilegedRun.outcome(status: 1,
                                  output: "0:18: execution error: Не удается получить «script». (-1728)"),
            .failed(1))
    }
}
