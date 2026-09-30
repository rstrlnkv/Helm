import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **`brew doctor` is asked for uncoloured output, and only `brew doctor` is.**
///
/// `HOMEBREW_COLOR=1` — from the environment or from a `brew.env` file brew
/// reads itself — puts an escape in front of every `Warning:` on a non-terminal
/// stream, and `DoctorParser` finds a finding by that word at the start of a
/// line. `HOMEBREW_NO_COLOR` in what Helm hands over overrides the colour
/// (measured on this Mac, Homebrew 7.0.7, 2026-09-29: the output is byte for
/// byte the plain one).
///
/// `ADoctorThatNamedNothingReadableIsNotACleanMacTests` accepts either of two
/// repairs for a coloured doctor — no colour asked, or exit 1 with nothing
/// parsed refused — because a refusal alone also stops «Nothing to fix.». This
/// file is the check that only the first can pass: the coloured Mac is read
/// as its two findings, not as an answer nobody could read.
///
/// The second half keeps the variable out of `brew config`, which echoes the
/// variables brew sees (`HOMEBREW_COLOR: set` was measured there), so the text
/// a person copies into a bug report would name one of Helm's own.
private final class RecordingRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _envs: [String: [String: String]] = [:]
    func env(for verb: String) -> [String: String]? { lock.lock(); defer { lock.unlock() }; return _envs[verb] }

    var coloured = ""
    var plain = ""

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); _envs[args.first ?? ""] = env; lock.unlock()
        return (0, "HOMEBREW_VERSION: 7.0.7\nHOMEBREW_PREFIX: /opt/homebrew\n")
    }

    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        lock.lock(); _envs[args.first ?? ""] = env; lock.unlock()
        return (1, (env["HOMEBREW_NO_COLOR"] ?? "").isEmpty ? coloured : plain)
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
    func runAdmin(_ script: String) -> PrivilegedOutcome { .declined }
}

final class TheDoctorIsAskedForPlainTextTests: XCTestCase {

    private static let esc = "\u{1B}"
    private static let plain = """
        Warning: /usr/bin occurs before /opt/homebrew/bin in your PATH.
        This means that system-provided programs will be used instead of those
        provided by Homebrew.

        Warning: Homebrew's "sbin" was not found in your PATH but you have installed
        formulae that put executables in /opt/homebrew/sbin.

        """
    private static let coloured = plain.replacingOccurrences(
        of: "Warning:", with: "\(esc)[33mWarning:\(esc)[0m")

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    func testAColouredMacIsReadAsItsTwoFindings() {
        let runner = RecordingRunner()
        runner.plain = Self.plain
        runner.coloured = Self.coloured
        XCTAssertEqual(engine(runner).doctor()?.count, 2,
                       "doctor was not asked for plain text, so its findings did not parse")
        XCTAssertEqual(runner.env(for: "doctor")?["HOMEBREW_NO_COLOR"], "1")
        XCTAssertEqual(runner.env(for: "doctor")?["HOMEBREW_NO_AUTO_UPDATE"], "1",
                       "the doctor's environment is the query environment plus the colour switch")
    }

    func testOnlyTheDoctorCarriesIt() {
        let runner = RecordingRunner()
        _ = engine(runner).config()
        let seen = runner.env(for: "config")
        XCTAssertNotNil(seen, "config never reached the runner, so the absence below proves nothing")
        XCTAssertEqual(seen, HomebrewEngine.queryEnvironment)
        XCTAssertNil(seen?["HOMEBREW_NO_COLOR"])
    }
}
