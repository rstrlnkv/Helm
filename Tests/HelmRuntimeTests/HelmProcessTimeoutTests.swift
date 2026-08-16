import XCTest
import HelmTestSupport
@testable import HelmRuntime

/// `HelmProcess.run` blocks until the tool closes its output — which for a tool
/// that has hung (a brew waiting on another brew's lock, an installer waiting
/// for input nobody can give) is never. The caller's thread is parked for the
/// life of the process, and everything behind it queues. A deadline turns that
/// into an answer: a named status, promptly.
final class HelmProcessTimeoutTests: XCTestCase {

    /// The failure being looked for is a hang; it must be reported, not waited
    /// on. `/bin/sleep` writes nothing and exits in 30 s — far past the suite's
    /// patience, well within the machine's.
    func testAHungToolIsCutOffAtTheDeadline() {
        let started = Date()
        let result = HelmProcess.run("/bin/sleep", ["30"], timeout: 0.3)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(result.status, HelmProcess.timedOutStatus,
                       "a tool that never answered came back as something other than a timeout")
        XCTAssertLessThan(elapsed, 10,
                          "the deadline passed at 0.3 s and run returned only after \(elapsed) s")
    }

    /// The deadline is not delivered by abandoning the child: it is terminated.
    /// The shell traps TERM and leaves a marker, which is the only way to see
    /// from outside that the signal arrived. (`sleep` runs in the background and
    /// `wait` is interruptible, so the trap fires at the signal rather than
    /// after the sleep.)
    func testTheChildIsTerminatedNotAbandoned() {
        let dir = scratchDirectory("process-timeout")
        let marker = dir.appendingPathComponent("terminated")
        let script = "trap 'echo gone > \"\(marker.path)\"; exit 0' TERM; sleep 30 & wait"
        _ = HelmProcess.run("/bin/sh", ["-c", script], timeout: 0.3)
        // The trap needs a moment to write after the signal lands.
        for _ in 0..<200 where !FileManager.default.fileExists(atPath: marker.path) {
            usleep(10_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path),
                      "the deadline passed and the child was left running")
    }

    /// A tool that answers in time is untouched: same status, same output as
    /// the deadline-free path.
    func testAToolThatAnswersInTimeIsUntouched() {
        let result = HelmProcess.run("/bin/sh", ["-c", "printf hi; exit 3"], timeout: 5)
        XCTAssertEqual(result.status, 3)
        XCTAssertEqual(result.output, "hi")
    }
}
