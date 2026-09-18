import XCTest
@testable import Module_Homebrew_Engine

/// `HomebrewEngine.doctor()` — the query this task adds.
///
/// **The fixture below is captured verbatim**, independently of
/// `DoctorParserTests`' copy, from:
///
///     $ /opt/homebrew/bin/brew doctor > /tmp/doc.out 2> /tmp/doc.err; echo "exit=$?"
///     exit=1
///     $ wc -c /tmp/doc.out /tmp/doc.err
///        1 /tmp/doc.out
///     1194 /tmp/doc.err
///
/// on this machine, Homebrew 7.0.1, 2026-09-15 — the same measurement the
/// module's doc comments cite. It holds two distinct issues once the repeated
/// `postflight` block collapses: a tap's `postflight` deprecation and «Some
/// installed formulae are deprecated or disabled».
///
/// This file is not `DoctorParserTests`, which already proves the parser
/// against this text in detail — it proves the *query*: that the engine
/// reaches for the diagnostics stream rather than `run`, and that a non-zero
/// exit from `brew doctor` (its ordinary shape, per the plan's measurement)
/// does not get read as a refusal.
private final class DoctorRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _diagnosticsCalls: [[String]] = []
    var diagnosticsCalls: [[String]] { lock.lock(); defer { lock.unlock() }; return _diagnosticsCalls }
    private var _runCalls = 0
    var runCalls: Int { lock.lock(); defer { lock.unlock() }; return _runCalls }

    /// What `runCapturingDiagnostics` answers — this is the only stream the
    /// real `brew doctor` writes anything useful to.
    var status: Int32 = 1
    var output = ""

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        // The real `run` sends stderr to the null device, and `brew doctor`
        // prints nothing else — so a query that mistakenly used this method
        // would see exactly what is returned here: one empty byte, nothing
        // the parser can read as an issue.
        lock.lock(); _runCalls += 1; lock.unlock()
        return (0, "")
    }

    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        lock.lock(); _diagnosticsCalls.append(args); lock.unlock()
        return (status, output)
    }

    func stream(_ launchPath: String, _ args: [String], env: [String: String],
                onLine: @escaping @Sendable (String) -> Void,
                onExit: @escaping @Sendable (Int32) -> Void) -> RunningProcess {
        onExit(0)
        return NoProcess()
    }
}

private struct FixedLocator: BrewLocator {
    func brewPath() -> String? { "/opt/homebrew/bin/brew" }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

final class ADoctorReadingIsNotGatedOnExitStatusTests: XCTestCase {

    /// Captured independently of `DoctorParserTests`' copy — see the file's
    /// doc comment. Byte-for-byte what `/tmp/doc.err` held on this machine.
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

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    /// Case 1: a fake whose diagnostics carry this machine's real captured
    /// output answers two issues — the ordinary path, exit status matching
    /// what the plan measured (1).
    func testRealCapturedOutputAnswersTwoIssues() {
        let runner = DoctorRunner()
        runner.status = 1
        runner.output = Self.capturedOutput
        let issues = engine(runner).doctor()
        XCTAssertEqual(issues?.count, 2,
                       "real captured doctor output must parse into its two distinct issues")
        XCTAssertEqual(runner.diagnosticsCalls.first, ["doctor"])
    }

    /// Case 2: a fake that answers nothing at all answers nil — the module
    /// must not read silence (an unset fixture, a refused or never-run
    /// query) as a clean machine. This is `DoctorParser.parse`'s own
    /// empty-input case, reached through the query.
    func testNoDiagnosticsAtAllAnswersNil() {
        let runner = DoctorRunner()
        runner.status = 1
        runner.output = ""
        XCTAssertNil(engine(runner).doctor(),
                     "empty diagnostics must not read as «doctor ran and found nothing»")
    }

    /// Case 3: the exit-status trap, as its own case. `brew doctor` exits 1
    /// whenever it has something to say (measured above) — a query that
    /// treated that non-zero exit as a refusal would report a clean machine
    /// exactly when the machine is not clean. Same real output as case 1,
    /// same exit status Homebrew actually produced; stated on its own so a
    /// regression that starts gating on `result.status != 0` fails here even
    /// if it left case 1 alone.
    func testANonZeroExitWithRealOutputStillAnswersTwoIssues() {
        let runner = DoctorRunner()
        runner.status = 1
        runner.output = Self.capturedOutput
        let issues = engine(runner).doctor()
        XCTAssertEqual(issues?.count, 2,
                       "exit 1 is brew doctor's ordinary shape when it has something to say — "
                       + "it must not be read as a refusal")
    }

    /// Case 4: the runner method actually used is `runCapturingDiagnostics`
    /// and not `run` — asserted at the fake, because the substitution is
    /// invisible everywhere else: `run` here answers `(0, "")`, exactly what
    /// the real `ShellProcessRunner.run` would answer for `brew doctor` (one
    /// empty byte of stdout, stderr sent to the null device), so a query that
    /// used `run` by mistake would still build, still run, and would simply
    /// go on answering nil forever with no error anywhere in the page.
    func testTheQueryUsesTheDiagnosticsCapturingRunnerAndNotPlainRun() {
        let runner = DoctorRunner()
        runner.status = 1
        runner.output = Self.capturedOutput
        _ = engine(runner).doctor()
        XCTAssertEqual(runner.diagnosticsCalls.count, 1,
                       "the query must call runCapturingDiagnostics exactly once")
        XCTAssertEqual(runner.runCalls, 0,
                       "the query must never call plain run — brew doctor's whole answer "
                       + "is on the stream run does not carry")
    }
}
