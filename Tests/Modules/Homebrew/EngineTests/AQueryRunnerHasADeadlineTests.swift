import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// Every fast Homebrew query blocks on `ShellProcessRunner.run` until the tool
/// closes its output. A brew that hangs — another brew's lock, a network stall,
/// an installer waiting for input nobody can give — used to park that thread for
/// the life of the process: the page's spinner never stopped and the module was
/// dead until the app restarted. The runner bounds the wait now.
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

    /// The default is not a test value: it has to clear the slowest real query
    /// with room. The owner's log has warm queries at 0.3–0.6 s and a cold
    /// `brew outdated` (which goes to the network) at 7.4 s; the default must
    /// stand well above that and still end a hang within a minute.
    func testTheDefaultDeadlineClearsTheSlowestMeasuredQueryTenfold() {
        XCTAssertGreaterThanOrEqual(ShellProcessRunner.defaultQueryTimeout, 74,
                                    "cold brew outdated was measured at 7.4 s; the deadline must clear it tenfold")
        XCTAssertLessThanOrEqual(ShellProcessRunner.defaultQueryTimeout, 180,
                                 "a spinner that runs for minutes is the hang this deadline exists to end")
    }
}
