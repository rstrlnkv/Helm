import XCTest
@testable import Module_Homebrew_Engine

/// `DoctorParser.parse` against `brew doctor`'s real answer.
///
/// The fixture below is captured verbatim — not tidied, not reduced to two
/// invented duplicates — from:
///
///     $ /opt/homebrew/bin/brew doctor > /tmp/doctor.out 2> /tmp/doctor.err
///     exit=1
///        1 /tmp/doctor.out
///     1194 /tmp/doctor.err
///
/// on this machine, Homebrew 7.0.1, 2026-09-15. It holds a tap's `postflight`
/// deprecation warning three times, brew's own aside to the reader sitting
/// *between* the second and third repeat rather than only at the end, and
/// «Some installed formulae are deprecated or disabled» naming `periphery` on
/// its own indented line.
final class DoctorParserTests: XCTestCase {

    /// Byte-for-byte what `/tmp/doctor.err` held. Reused across cases so a
    /// slip while retyping the fixture cannot make two tests disagree about
    /// what "real output" is.
    private static let capturedOutput = """
        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        Please note that these warnings are just used to help the Homebrew maintainers
        with debugging if you file an issue. If everything you use Homebrew for is
        working fine: please don't worry or file an issue; just ignore this. Thanks!

        Warning: Some installed formulae are deprecated or disabled.
        You should find replacements for the following formulae:

          periphery
        Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
        Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
          /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18

        """

    /// The real repetition collapses to one issue: three identical
    /// `postflight` blocks (indices 0, 1 and the very last block in the
    /// fixture) must read back as a single entry, not three, and the
    /// disclaimer paragraph sitting between the second and third repeat must
    /// not have leaked into any of their bodies — if it had, the second copy
    /// would carry different text from the first and dedup would fail to
    /// collapse them, so this single equality assertion is what catches that.
    func testTwoDistinctIssuesWithTheRepeatedBlockCollapsed() {
        let postflightBody = """
            Please report this issue to the sozercan/homebrew-repo tap (not Homebrew/* repositories), or even better, submit a PR to fix it:
              /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18
            """
        let deprecatedFormulaeBody = """
            You should find replacements for the following formulae:

              periphery
            """
        let expected = [
            DoctorIssue(
                severity: .caution,
                title: "Calling `postflight` is deprecated! Use `postflight_steps` instead.",
                body: postflightBody),
            DoctorIssue(
                severity: .caution,
                title: "Some installed formulae are deprecated or disabled.",
                body: deprecatedFormulaeBody),
        ]

        XCTAssertEqual(DoctorParser.parse(Self.capturedOutput), expected)
    }

    /// A body line naming a path is kept exactly as brew printed it —
    /// including its leading two spaces — because this module does not
    /// re-spell somebody's paths. Failing this while the count-and-equality
    /// test above still passes would mean the assertion above stopped being
    /// specific enough on its own; this pins the one line that matters most.
    func testAPathInABodyLineSurvivesVerbatim() {
        let issues = DoctorParser.parse(Self.capturedOutput)
        XCTAssertEqual(
            issues?.first?.body.components(separatedBy: "\n").last,
            "  /opt/homebrew/Library/Taps/sozercan/homebrew-repo/Casks/kaset.rb:18")
    }

    /// `Error:` and `Warning:` map to distinct severities. Homebrew 7.0.1
    /// produced no `Error:` line on this machine, so this half of the fixture
    /// is a small, isolated string rather than a real capture — unlike the
    /// repetition above, nothing here depends on this being brew's own text.
    func testErrorIsDangerAndWarningIsCaution() {
        let text = "Error: Your Command Line Tools are outdated.\nRun `xcode-select --install`.\n"
        let issues = DoctorParser.parse(text)

        XCTAssertEqual(issues?.count, 1)
        XCTAssertEqual(issues?.first?.severity, .danger)
        XCTAssertEqual(issues?.first?.title, "Your Command Line Tools are outdated.")

        let warningText = "Warning: Something is off.\nA detail.\n"
        XCTAssertEqual(DoctorParser.parse(warningText)?.first?.severity, .caution)
    }

    /// Real output naming no `Warning:`/`Error:` line at all — brew's own
    /// aside to the reader, lifted verbatim from the middle of the captured
    /// fixture above — reads as "doctor ran and found nothing": an empty
    /// array, not nil.
    func testOutputWithNoWarningOrErrorLineIsAnEmptyArray() {
        let prose = """
            Please note that these warnings are just used to help the Homebrew maintainers
            with debugging if you file an issue. If everything you use Homebrew for is
            working fine: please don't worry or file an issue; just ignore this. Thanks!
            """

        XCTAssertEqual(DoctorParser.parse(prose), [])
    }

    /// Empty input is nil — the tool said nothing, which is not the same
    /// claim as "the tool ran and the machine is clean". This is the case the
    /// stderr measurement exists to guard: get it wrong and a refused or
    /// never-run query reads as a healthy machine.
    func testEmptyInputIsNil() {
        XCTAssertNil(DoctorParser.parse(""))
    }
}
