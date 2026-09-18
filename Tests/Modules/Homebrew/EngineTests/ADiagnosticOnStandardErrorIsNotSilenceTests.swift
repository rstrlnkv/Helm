import XCTest
@testable import Module_Homebrew_Engine

/// `brew doctor` prints its entire answer on standard error and nothing on
/// standard output (measured on this Mac, 2026-09-14, Homebrew 7.0.1: 1 byte
/// of stdout against 1,194 of stderr). Every other query in this module is
/// parsed, and `ShellProcessRunner.run` sends standard error to the null
/// device *on purpose* — a tap's deprecation warning would otherwise become a
/// package name — so `run` pointed at `doctor` comes back empty. This is the
/// one query whose whole answer is on the wrong stream, and the one method
/// that goes and gets it.
final class ADiagnosticOnStandardErrorIsNotSilenceTests: XCTestCase {

    private let script = "echo out; echo err 1>&2"

    /// The method this task adds: both streams, in the order the child wrote
    /// them.
    func testBothStreamsArriveInWriteOrder() {
        let result = ShellProcessRunner().runCapturingDiagnostics("/bin/sh", ["-c", script], env: [:])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "out\nerr\n",
                       "standard output and standard error must arrive together, in the order the child wrote them")
    }

    /// The half that matters: `run` on the very same child carries only what
    /// the child wrote to stdout. This is *why* `runCapturingDiagnostics`
    /// exists rather than a change to `run` — every other parser in this
    /// module depends on `run` staying silent about diagnostics, and this
    /// assertion is what breaks first if somebody later merges the streams
    /// there instead.
    func testPlainRunCarriesOnlyStandardOutput() {
        let result = ShellProcessRunner().run("/bin/sh", ["-c", script], env: [:])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "out\n",
                       "plain run must not carry standard error — every other parser in this module assumes that")
    }
}
