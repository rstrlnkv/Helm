import HelmTestSupport
import XCTest
@testable import Module_Homebrew_Engine

/// The port every fast Homebrew query goes through.
///
/// `listInstalled`, `outdated`, `descriptions` and `search` all call
/// `ShellProcessRunner.run` and parse what comes back, so whatever happens here
/// happens to the Homebrew page.
final class ShellProcessRunnerTests: XCTestCase {

    /// Runs `body` on a background queue and fails rather than hanging the
    /// suite. A hung run is the failure being looked for; it must be reported,
    /// not waited on.
    private func withinTimeout(_ seconds: TimeInterval,
                               _ body: @escaping @Sendable () -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { body(); done.signal() }
        return done.wait(timeout: .now() + seconds) == .success
    }

    /// A tool that says a lot on stderr.
    ///
    /// A pipe holds about 64 KB. A stderr nobody reads blocks the child in
    /// `write(2)`, so it never exits, never closes stdout, and the read of
    /// stdout never returns: two processes waiting on each other, the hazard
    /// `HelmProcess`'s header describes for the stdout side.
    ///
    /// `brew` says a lot on stderr: a deprecation warning per formula from
    /// `outdated`, an `Error: No available formula…` per missing name from
    /// `desc`, a git failure from `search` against a cold tap. Past 64 KB any of
    /// them would park the queue and leave the page's spinner running.
    ///
    /// The child kills itself after five seconds so this test reports rather
    /// than hangs.
    func testAChattyStderrDoesNotStallTheRun() {
        // ~200 KB on stderr, comfortably past a pipe's capacity, then one line
        // on stdout. Shell built-ins only: an extra process would hold the
        // pipes open past the watchdog and confuse the result.
        let script = """
        ( sleep 5; kill -9 $$ ) >/dev/null 2>&1 &
        i=0
        while [ $i -lt 2000 ]; do
          printf '%s\\n' '\(String(repeating: "w", count: 99))' >&2
          i=$((i+1))
        done
        printf 'ada-url 3.4.4\\n'
        """
        let box = Locked<(status: Int32, stdout: String)?>(nil)
        let finished = withinTimeout(15) {
            box.value = ShellProcessRunner().run("/bin/sh", ["-c", script], env: [:])
        }
        XCTAssertTrue(finished, "run never returned at all")
        let result = box.value
        XCTAssertEqual(result?.status, 0,
                       "the child was killed by the watchdog (signal status \(result?.status ?? -1)) "
                       + "— it was blocked writing to an stderr pipe nobody reads")
        XCTAssertEqual(result?.stdout, "ada-url 3.4.4\n",
                       "stdout that was written after the stderr chatter never arrived")
    }

    /// The control: the same amount of output on stdout is read, because that
    /// pipe has a reader. Proves the test above is about the missing stderr
    /// reader and not about the volume.
    func testTheSameVolumeOnStdoutIsFine() {
        let script = """
        i=0
        while [ $i -lt 2000 ]; do
          printf '%s\\n' '\(String(repeating: "w", count: 99))'
          i=$((i+1))
        done
        """
        let box = Locked<(status: Int32, stdout: String)?>(nil)
        let finished = withinTimeout(15) {
            box.value = ShellProcessRunner().run("/bin/sh", ["-c", script], env: [:])
        }
        XCTAssertTrue(finished, "run never returned")
        XCTAssertEqual(box.value?.status, 0)
        XCTAssertEqual(box.value?.stdout.split(separator: "\n").count, 2000)
    }

    /// The status is the tool's own, and a failure has to be distinguishable
    /// from an empty answer — every caller here turns "" into an empty list.
    func testAFailedToolReportsItsStatus() {
        let box = Locked<(status: Int32, stdout: String)?>(nil)
        _ = withinTimeout(15) {
            box.value = ShellProcessRunner().run("/bin/sh", ["-c", "exit 17"], env: [:])
        }
        XCTAssertEqual(box.value?.status, 17)
    }
}
