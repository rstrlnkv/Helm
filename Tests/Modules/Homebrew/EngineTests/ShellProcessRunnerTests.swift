import XCTest
@testable import Module_Homebrew_Engine

/// The port every fast Homebrew query goes through.
///
/// `listInstalled`, `outdated`, `descriptions` and `search` all call
/// `ShellProcessRunner.run` and parse what comes back. It answers on a dispatch
/// queue borrowed from the transport, so whatever happens here happens to the
/// Homebrew page.
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

    /// The trap: a tool that says a lot on stderr.
    ///
    /// `run` delegates to `HelmProcess.run`, which sets `standardError` to a
    /// fresh `Pipe()` and never reads it. A pipe holds about 64 KB. Past that
    /// the child blocks in `write(2)` on stderr — so it never exits, never
    /// closes stdout, and the `readDataToEndOfFile()` on stdout never returns.
    /// Two processes waiting on each other, which is the exact hazard
    /// `HelmProcess`'s own header describes for the stdout side and fixes there
    /// by reading before waiting. The stderr side has no reader at all.
    ///
    /// `brew` is a tool that says a lot on stderr: a deprecation warning per
    /// formula from `outdated`, an `Error: No available formula with the name…`
    /// per missing name from the `desc` call the page makes with the whole
    /// installed list, a git failure from `search` against a cold tap. None of
    /// them is exotic and any of them past 64 KB parks the queue for the life
    /// of the process. The page shows its spinner and never stops.
    ///
    /// The child kills itself after five seconds so this test reports rather
    /// than hangs; nothing rescues the real app.
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
        let box = Box()
        let finished = withinTimeout(15) {
            box.result = ShellProcessRunner().run("/bin/sh", ["-c", script], env: [:])
        }
        XCTAssertTrue(finished, "run never returned at all")
        let result = box.result
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
        let box = Box()
        let finished = withinTimeout(15) {
            box.result = ShellProcessRunner().run("/bin/sh", ["-c", script], env: [:])
        }
        XCTAssertTrue(finished, "run never returned")
        XCTAssertEqual(box.result?.status, 0)
        XCTAssertEqual(box.result?.stdout.split(separator: "\n").count, 2000)
    }

    /// The status is the tool's own, and a failure has to be distinguishable
    /// from an empty answer — every caller here turns "" into an empty list.
    func testAFailedToolReportsItsStatus() {
        let box = Box()
        _ = withinTimeout(15) {
            box.result = ShellProcessRunner().run("/bin/sh", ["-c", "exit 17"], env: [:])
        }
        XCTAssertEqual(box.result?.status, 17)
    }

    private final class Box: @unchecked Sendable {
        var result: (status: Int32, stdout: String)?
    }
}
