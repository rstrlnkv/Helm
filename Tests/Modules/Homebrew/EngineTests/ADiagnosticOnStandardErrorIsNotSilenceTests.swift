import XCTest
@testable import Module_Homebrew_Engine

/// `brew doctor` prints its entire answer on standard error and nothing on
/// standard output. `ShellProcessRunner.run` sends standard error to the null
/// device *on purpose*, since a tap's deprecation warning would otherwise become
/// a package name, so `run` pointed at `doctor` comes back empty.
/// `runCapturingDiagnostics` is the one method that reads both streams.
final class ADiagnosticOnStandardErrorIsNotSilenceTests: XCTestCase {

    private let script = "echo out; echo err 1>&2"

    /// Both streams, in the order the child wrote them.
    func testBothStreamsArriveInWriteOrder() {
        let result = ShellProcessRunner().runCapturingDiagnostics("/bin/sh", ["-c", script], env: [:])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, "out\nerr\n",
                       "standard output and standard error must arrive together, in the order the child wrote them")
    }

    /// `run` on the same child carries only what it wrote to stdout: every other
    /// parser in this module depends on `run` staying silent about diagnostics,
    /// which is why the merge lives in a separate method.
    func testPlainRunCarriesOnlyStandardOutput() {
        let result = ShellProcessRunner().run("/bin/sh", ["-c", script], env: [:])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.stdout, "out\n",
                       "plain run must not carry standard error — every other parser in this module assumes that")
    }
}
