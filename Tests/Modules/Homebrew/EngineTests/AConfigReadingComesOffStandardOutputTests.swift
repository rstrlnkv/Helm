import XCTest
@testable import Module_Homebrew_Engine

/// `HomebrewEngine.config()` — the query, not the parser.
///
/// **The fixture is captured verbatim**, independently of
/// `BrewConfigParserTests`' copy, from:
///
///     $ /opt/homebrew/bin/brew config > /tmp/cfg.out 2> /tmp/cfg.err; echo "exit=$?"
///     exit=0
///     $ wc -c /tmp/cfg.out /tmp/cfg.err
///     555 /tmp/cfg.out
///       0 /tmp/cfg.err
///
/// on this machine, Homebrew 7.0.1, 2026-09-15.
///
/// **That measurement is the opposite of `brew doctor`'s on every count that
/// decides this query's shape**, which is why this file exists beside
/// `ADoctorReadingIsNotGatedOnExitStatusTests` rather than copying it: the
/// answer is on standard output, so the runner is plain `run`; the exit status
/// is 0, so a non-zero one is brew declining rather than part of the answer.
/// Taking `doctor`'s two choices here would be wrong twice over, and both
/// mistakes are invisible on a fake that answers everything.
private final class ConfigRunner: ProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _runCalls: [[String]] = []
    var runCalls: [[String]] { lock.lock(); defer { lock.unlock() }; return _runCalls }
    private var _diagnosticsCalls = 0
    var diagnosticsCalls: Int { lock.lock(); defer { lock.unlock() }; return _diagnosticsCalls }

    var status: Int32 = 0
    var output = ""

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) {
        lock.lock(); _runCalls.append(args); lock.unlock()
        return (status, output)
    }

    /// **Answers the same document as `run`, on purpose.** A fake that answered
    /// nothing here would let the call-site assertion below pass for the wrong
    /// reason — the query would fail loudly instead of quietly. With both
    /// methods answering, a query that reached for the wrong stream parses
    /// perfectly and only the count of calls can see it.
    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        lock.lock(); _diagnosticsCalls += 1; lock.unlock()
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

private struct NoBrew: BrewLocator {
    func brewPath() -> String? { nil }
}

private struct NoPrivileges: PrivilegedRunner {
    func runAdmin(_ script: String) -> Bool { false }
}

final class AConfigReadingComesOffStandardOutputTests: XCTestCase {

    /// Byte-for-byte what `/tmp/cfg.out` held — captured independently of
    /// `BrewConfigParserTests`' copy, so a slip in one cannot make the other
    /// agree with it.
    private static let capturedOutput = """
        HOMEBREW_VERSION: 7.0.1
        ORIGIN: https://github.com/Homebrew/brew
        HEAD: b3625f73d3e3574c5789ee32eb7b06627b788ec4
        Last commit: 2 days ago
        Branch: stable
        Core tap: N/A
        Core cask tap: N/A
        HOMEBREW_PREFIX: /opt/homebrew
        Homebrew Ruby: 4.0.6 => /opt/homebrew/Library/Homebrew/vendor/portable-ruby/4.0.6_2/bin/ruby
        CPU: 11-core 64-bit arm_lobos
        Clang: 21.0.0 build 2100
        Git: 2.54.0 => /Applications/Xcode.app/Contents/Developer/usr/bin/git
        Curl: 8.7.1 => /usr/bin/curl
        macOS: 27.0-arm64
        CLT: 27.0.0.0.1788430756
        Xcode: 27.0
        Metal Toolchain: N/A
        Rosetta 2: false

        """

    private func engine(_ runner: ProcessRunner,
                        locator: BrewLocator = FixedLocator()) -> HomebrewEngine {
        HomebrewEngine(locator: locator, runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    /// The ordinary path: exit 0, the real document, eighteen lines and the
    /// argv brew was actually given.
    func testTheRealDocumentAnswersEveryLine() throws {
        let runner = ConfigRunner()
        runner.output = Self.capturedOutput
        let config = try XCTUnwrap(engine(runner).config())

        XCTAssertEqual(config.lines.count, 18)
        XCTAssertEqual(runner.runCalls.first, ["config"],
                       "the query passed brew something other than `config`")
    }

    /// **The runner actually used is plain `run`.**
    ///
    /// The mirror image of `brew doctor`'s case, and the brief for this feature
    /// named it as the trap: `doctor` needs `runCapturingDiagnostics` because
    /// its whole answer is on standard error, and copying that choice here
    /// would fold a tap's deprecation warning into the document — a warning's
    /// own colon then parses as a configuration key, and the page draws a row
    /// naming something that is not a setting.
    ///
    /// Asserted at the fake, because the substitution is invisible everywhere
    /// else: this fake answers the same document from both methods, so a query
    /// on the wrong one parses perfectly and nothing downstream differs.
    func testTheQueryUsesPlainRunAndNotTheDiagnosticsCapturingRunner() {
        let runner = ConfigRunner()
        runner.output = Self.capturedOutput
        _ = engine(runner).config()

        XCTAssertEqual(runner.runCalls.count, 1, "the query must call `run` exactly once")
        XCTAssertEqual(runner.diagnosticsCalls, 0, """
            the query reached for the diagnostics stream, which `brew config` writes nothing to \
            (0 bytes of stderr, measured) and which carries whatever else brew felt like saying
            """)
    }

    /// **`text` is the document and not a rebuild of the reading.**
    ///
    /// The one thing «Copy for a bug report» depends on. The fixture below is
    /// the real document cut off mid-key, which is what a run ended at a
    /// deadline leaves: the parser drops that partial line, and a `text`
    /// composed back out of `lines` would drop it too — so what reaches
    /// somebody's issue tracker would be Helm's reading of brew's answer rather
    /// than brew's answer.
    func testTheDocumentIsCarriedWholeAndNotRebuiltFromTheReading() throws {
        let runner = ConfigRunner()
        runner.output = "HOMEBREW_VERSION: 7.0.1\nMetal Tool"
        let config = try XCTUnwrap(engine(runner).config())

        XCTAssertEqual(config.lines.map(\.key), ["HOMEBREW_VERSION"],
                       "precondition: the parser dropped the partial line")
        XCTAssertEqual(config.text, "HOMEBREW_VERSION: 7.0.1\nMetal Tool", """
            the text carried is not what brew printed — a bug report would carry Helm's reading \
            of the document instead of the document
            """)
    }

    /// A non-zero exit is brew declining. Measured: `brew config` exits 0, so
    /// unlike `brew doctor` a non-zero exit here is never part of the answer —
    /// and `completed` (the helper `doctor` needs) would read the document
    /// anyway and draw a configuration off a run that failed.
    func testANonZeroExitIsARefusalAndNotAReading() {
        let runner = ConfigRunner()
        runner.status = 1
        runner.output = Self.capturedOutput
        XCTAssertNil(engine(runner).config(), """
            brew declined — exit 1 where it always exits 0 — and the engine drew a configuration \
            off it anyway
            """)
    }

    /// No brew to ask is nil, and nothing is run.
    func testNoBrewIsNilAndRunsNothing() {
        let runner = ConfigRunner()
        runner.output = Self.capturedOutput
        XCTAssertNil(engine(runner, locator: NoBrew()).config())
        XCTAssertEqual(runner.runCalls.count, 0)
    }

    /// Output this build cannot read as `key: value` is nil rather than an
    /// empty configuration — `BrewConfigParser.parse`'s own rule, reached
    /// through the query.
    func testOutputWithNothingReadableInItIsNil() {
        let runner = ConfigRunner()
        runner.output = "==> Downloading\nsomething went wrong\n"
        XCTAssertNil(engine(runner).config())

        runner.output = ""
        XCTAssertNil(engine(runner).config())
    }
}
