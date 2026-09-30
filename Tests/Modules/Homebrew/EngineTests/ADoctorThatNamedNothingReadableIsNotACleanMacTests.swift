import XCTest
import HelmRuntime
@testable import Module_Homebrew_Engine

/// **`brew doctor` exiting 1 is brew saying the Mac is not clean**, and an
/// answer this module could not read a finding out of is then not «Nothing to
/// fix».
///
/// `cmd/doctor.rb` sets `Homebrew.failed` for every check that returns a
/// finding, and `ofail` sets it with no check having found anything; a Mac
/// with nothing to report exits 0 and prints «Your system is ready to brew.».
/// So exit 1 with no finding parsed is never a clean Mac, and the Health tab
/// draws `.examined([])` as its green verdict — «Nothing to fix.» over a Mac
/// brew has just said is not clean.
///
/// **The input nobody fed in: colour.** brew colours its output on a non-TTY
/// stream when `HOMEBREW_COLOR` is set, and it reads that variable not only
/// from the environment Helm passes but from `brew.env` files it loads itself
/// (`/etc/homebrew/brew.env`, `$HOMEBREW_PREFIX/etc/homebrew/brew.env`,
/// `~/.homebrew/brew.env`), where a line overrides the environment. Every
/// `Warning:` then arrives as `ESC[33mWarning:ESC[0m`, which `DoctorParser`
/// does not see as a block start. `HOMEBREW_NO_COLOR` wins over it
/// (`Tty.color?` asks `no_color?` first).
///
/// Both fixtures below were captured on this Mac, Homebrew 7.0.7, 2026-09-29,
/// with a `PATH` that puts `/usr/bin` first so doctor has something to say:
///
///     $ env PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin HOMEBREW_NO_AUTO_UPDATE=1 \
///           [HOMEBREW_COLOR=1] /opt/homebrew/bin/brew doctor > out 2>&1; echo "EXIT=$?"
///     EXIT=1        (808 bytes plain, 834 coloured)
///
/// and `HOMEBREW_COLOR=1 HOMEBREW_NO_COLOR=1` printed the plain bytes exactly.
/// The fake answers as brew does: coloured unless the environment it is handed
/// says `HOMEBREW_NO_COLOR` — so either repair (asking brew for no colour, or
/// refusing to read exit 1 with nothing parsed as clean) turns this green.
private final class ColouringDoctor: ProcessRunner, @unchecked Sendable {
    var status: Int32 = 1
    var coloured = ""
    var plain = ""

    func run(_ launchPath: String, _ args: [String],
             env: [String: String]) -> (status: Int32, stdout: String) { (0, "") }

    func runCapturingDiagnostics(_ launchPath: String, _ args: [String],
                                 env: [String: String]) -> (status: Int32, output: String) {
        // `brew.env` says HOMEBREW_COLOR=1; only HOMEBREW_NO_COLOR (or NO_COLOR,
        // its documented default) in what Helm hands over switches it off.
        let noColour = !(env["HOMEBREW_NO_COLOR"] ?? "").isEmpty || !(env["NO_COLOR"] ?? "").isEmpty
        return (status, noColour ? plain : coloured)
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

final class ADoctorThatNamedNothingReadableIsNotACleanMacTests: XCTestCase {

    private static let esc = "\u{1B}"

    /// The body both captures share after their first line.
    private static func capture(warning: String, bold: String, reset: String) -> String {
        """
        \(bold)Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!\(reset)

        \(warning) /usr/bin occurs before /opt/homebrew/bin in your PATH.
        This means that system-provided programs will be used instead of those
        provided by Homebrew.

        The following tools exist at both paths:
          openssl
          pip3
          pp
          python3

        Consider setting your PATH for example like so:
          echo 'export PATH=/opt/homebrew/bin:$PATH' >> ~/.zshrc

        \(warning) Homebrew's "sbin" was not found in your PATH but you have installed
        formulae that put executables in /opt/homebrew/sbin.

        Consider setting your PATH for example like so:
          echo 'export PATH=/opt/homebrew/sbin:$PATH' >> ~/.zshrc


        """
    }

    private static let plain = capture(warning: "Warning:", bold: "", reset: "")
    private static let coloured = capture(warning: "\(esc)[33mWarning:\(esc)[0m",
                                          bold: "\(esc)[1m", reset: "\(esc)[0m")

    private func engine(_ runner: ProcessRunner) -> HomebrewEngine {
        HomebrewEngine(locator: FixedLocator(), runner: runner,
                       privileged: NoPrivileges(), user: "tester",
                       marker: InMemoryOpMarker())
    }

    /// The fixtures are what they claim: the plain capture parses into its two
    /// findings, and the byte counts match the measurement above — so a red
    /// below is about colour, not about a fixture nobody could parse.
    func testTheFixturesAreTheCapturedBytes() {
        XCTAssertEqual(Self.plain.utf8.count, 808)
        XCTAssertEqual(Self.coloured.utf8.count, 834)
        XCTAssertEqual(DoctorParser.parse(Self.plain)?.count, 2)
    }

    /// `brew.env` carries HOMEBREW_COLOR=1: doctor exits 1 with two findings
    /// in colour. The reading must be the two findings, or no reading — never
    /// an examined, empty one, which the page draws as «Nothing to fix.».
    func testAColouredDoctorIsNotReadAsNothingToFix() {
        let runner = ColouringDoctor()
        runner.status = 1
        runner.plain = Self.plain
        runner.coloured = Self.coloured
        let answer = engine(runner).doctor()
        XCTAssertNotEqual(answer, [],
                          "brew doctor exited 1 with two warnings in colour and Helm read it as a clean Mac")
        if let answer { XCTAssertEqual(answer.count, 2, "a reading, when there is one, holds both findings") }
    }

    /// The same contradiction with no colour in it: exit 1, and nothing that
    /// starts a block — the one byte of stdout `puts nil` leaves when stderr
    /// is lost (the measurement `ProcessRunner.runCapturingDiagnostics` cites)
    /// is exactly this. Exit 1 is brew saying it found something.
    func testExitOneWithNoFindingLineIsNotReadAsNothingToFix() {
        let runner = ColouringDoctor()
        runner.status = 1
        runner.plain = "\n"
        runner.coloured = "\n"
        XCTAssertNotEqual(engine(runner).doctor(), [],
                          "brew doctor exited 1 and printed no finding; Helm read it as a clean Mac")
    }

    /// The control: exit 0 and brew's own clean sentence is the one reading
    /// that is an examined, empty Mac — so the two above cannot pass by the
    /// engine refusing every empty answer.
    func testExitZeroWithTheReadySentenceIsAClean() {
        let runner = ColouringDoctor()
        runner.status = 0
        runner.plain = "Your system is ready to brew.\n"
        runner.coloured = "Your system is ready to brew.\n"
        XCTAssertEqual(engine(runner).doctor(), [])
    }
}
