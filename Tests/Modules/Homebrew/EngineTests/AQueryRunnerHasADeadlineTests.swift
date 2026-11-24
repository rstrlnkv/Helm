import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// Every fast Homebrew query blocks on `ShellProcessRunner.run` until the tool
/// closes its output. A brew that hangs (another brew's lock, a network stall,
/// an installer waiting for input) must not park that thread for the life of
/// the process, with the page's spinner never stopping.
///
/// The subject must really hang: a fake that answers synchronously makes a test
/// of a deadline vacuous. `/bin/sleep` writes nothing and stays for 30 s.
final class AQueryRunnerHasADeadlineTests: XCTestCase {

    func testAHungQueryComesBackAsATimeoutNotNever() {
        let runner = ShellProcessRunner(queryTimeout: 0.3)
        let started = Date()
        let result = runner.run("/bin/sleep", ["30"], env: [:])
        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "a hung query returned something other than the named timeout")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10,
                          "the runner waited past its own deadline")
    }

    /// **`runData` is a second body.** `run` serves the three text queries and
    /// `runData` serves `outdated`, which takes the bytes straight to
    /// `JSONDecoder`, so a deadline proven on one says nothing about the other.
    /// `outdated` is also the query that goes to the network. `/bin/sleep` dies
    /// on the TERM the deadline sends, so nothing is left running.
    func testTheBytesQueryHasTheSameDeadline() {
        let runner = ShellProcessRunner(queryTimeout: 0.3)
        let started = Date()
        let result = runner.runData("/bin/sleep", ["30"], env: [:])
        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "a hung `brew outdated` returned something other than the named timeout")
        XCTAssertTrue(result.stdout.isEmpty, "a query that never answered came back with bytes")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10,
                          "the bytes query waited past the runner's deadline")
    }

    /// `brew doctor` goes through `runCapturingDiagnostics`, which keeps the
    /// deadline too: a hung doctor is a timeout with no output, never a wait.
    func testTheDiagnosticsQueryHasTheSameDeadline() {
        let runner = ShellProcessRunner(queryTimeout: 0.3)
        let started = Date()
        let result = runner.runCapturingDiagnostics("/bin/sleep", ["30"], env: [:])
        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "a hung `brew doctor` returned something other than the named timeout")
        XCTAssertTrue(result.output.isEmpty, "a doctor that never answered came back with output")
        XCTAssertLessThan(Date().timeIntervalSince(started), 10,
                          "the diagnostics query waited past the runner's deadline")
    }

    /// The default is not a test value: it clears the slowest real query, a
    /// cold `brew outdated` that goes to the network (7.4 s), tenfold, and
    /// still ends a hang within a few minutes.
    func testTheDefaultDeadlineClearsTheSlowestMeasuredQueryTenfold() {
        XCTAssertGreaterThanOrEqual(ShellProcessRunner.defaultQueryTimeout, 74,
                                    "cold brew outdated was measured at 7.4 s; the deadline must clear it tenfold")
        XCTAssertLessThanOrEqual(ShellProcessRunner.defaultQueryTimeout, 180,
                                 "a spinner that runs for minutes is the hang this deadline exists to end")
    }
}
