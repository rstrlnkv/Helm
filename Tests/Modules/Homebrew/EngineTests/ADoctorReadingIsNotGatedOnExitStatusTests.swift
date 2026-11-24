import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// `HomebrewEngine.doctor()`, the query.
///
/// The fixture is `brew doctor`'s real standard error (exit 1, 1194 bytes),
/// captured independently of `DoctorParserTests`' copy. It holds two distinct
/// issues once the repeated `postflight` block collapses.
///
/// `DoctorParserTests` proves the parser against this text; this file proves
/// that the engine reads the diagnostics stream rather than `run`, and that
/// `brew doctor`'s ordinary non-zero exit is not read as a refusal.
final class ADoctorReadingIsNotGatedOnExitStatusTests: XCTestCase {

    /// What `runCapturingDiagnostics` answers, the only stream the real `brew
    /// doctor` writes anything useful to. `run` answers one empty byte, as the
    /// real one does with stderr sent to the null device.
    private func doctorRunner(status: Int32, output: String) -> ScriptedRunner {
        ScriptedRunner(diagnostics: { _ in (status, output) })
    }

    /// Byte-for-byte the captured standard error.
    private static let capturedOutput = """
        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!

        Warning: Some installed formulae are deprecated or disabled.
        You should find replacements for the following formulae:

          periphery
        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        """

    /// Case 1: real captured output answers two issues.
    func testRealCapturedOutputAnswersTwoIssues() {
        let runner = doctorRunner(status: 1, output: Self.capturedOutput)
        let issues = brewEngine(runner).doctor()
        XCTAssertEqual(issues?.count, 2,
                       "real captured doctor output must parse into its two distinct issues")
        XCTAssertEqual(runner.diagnosticsCalls.first, ["doctor"])
    }

    /// Case 2: a fake that answers nothing at all answers nil: silence (an
    /// unset fixture, a refused or never-run query) is not a clean machine.
    func testNoDiagnosticsAtAllAnswersNil() {
        let runner = doctorRunner(status: 1, output: "")
        XCTAssertNil(brewEngine(runner).doctor(),
                     "empty diagnostics must not read as «doctor ran and found nothing»")
    }

    /// Case 3: the exit-status trap on its own. `brew doctor` exits 1 whenever
    /// it has something to say, so a query that read that exit as a refusal
    /// would report a clean machine exactly when it is not.
    func testANonZeroExitWithRealOutputStillAnswersTwoIssues() {
        let runner = doctorRunner(status: 1, output: Self.capturedOutput)
        let issues = brewEngine(runner).doctor()
        XCTAssertEqual(issues?.count, 2,
                       "exit 1 is brew doctor's ordinary shape when it has something to say — "
                       + "it must not be read as a refusal")
    }

    /// Case 4: the runner method used is `runCapturingDiagnostics`, not `run`,
    /// asserted at the fake because the substitution is invisible elsewhere: a
    /// query on `run` would answer nil forever with no error on the page.
    func testTheQueryUsesTheDiagnosticsCapturingRunnerAndNotPlainRun() {
        let runner = doctorRunner(status: 1, output: Self.capturedOutput)
        _ = brewEngine(runner).doctor()
        XCTAssertEqual(runner.diagnosticsCalls.count, 1,
                       "the query must call runCapturingDiagnostics exactly once")
        XCTAssertEqual(runner.queries.count, 0,
                       "the query must never call plain run — brew doctor's whole answer "
                       + "is on the stream run does not carry")
    }
}
